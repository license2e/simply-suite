# Simply Suite Desktop App (Linux) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Simply Suite as a self-contained, offline **Linux** desktop app — an Electron window that supervises the unchanged Ruby/Puma server, with a user-configurable, safely-migratable data directory.

**Architecture:** Electron's main (Node) process picks a free loopback port, spawns the existing Sinatra app under Puma (dev: `bundle exec`; packaged: a bundled relocatable Ruby), waits on `/health` behind a splash, then loads `http://127.0.0.1:<port>` in a secure `BrowserWindow`. All data-directory logic (settings, first-run onboarding, checksum-verified migration) lives in the Electron layer; the Ruby app only ever receives a resolved `DATA_DIR`.

**Tech Stack:** Electron 33, Node's built-in test runner (`node:test`), electron-builder 25 (AppImage + deb), Ruby 3.3 / Sinatra 4 / Puma 8, RSpec + Rack::Test (existing).

**Scope:** This plan delivers the **complete Linux app** (spec Steps 0–1). macOS, Windows, CI matrix, and code-signing are follow-up plans (see "Follow-up plans" at the end) — they require other OSes, CI runners, and paid accounts that cannot be built or verified on this machine.

**Spec:** `docs/superpowers/specs/2026-07-12-desktop-app-electron-design.md`

## Global Constraints

- **Ruby app logic is untouched** except two additions: a `/health` route and `desktop_boot.rb`. No route/view/PDF/store changes.
- **Loopback only**: the server always binds `tcp://127.0.0.1:<port>`; never `0.0.0.0`.
- **Data folder is SS-owned**: SS only ever creates/deletes a dedicated folder. Default = `<userData>/data`; custom = `<picked>/Simply Suite`. A marker file `.simply-suite.json` (`{ "app": "simply-suite", "schema": 1 }`) identifies an SS data folder.
- **Migration is fail-safe**: on a later data-folder change, copy → verify **byte-for-byte (SHA-256 + size)** → **only then** delete the old folder. Any failure leaves the old folder and setting intact.
- **Conflict on later change**: if the chosen folder already holds SS data, prompt to *Adopt* (switch, no copy/delete) or *Cancel*. Never auto-overwrite.
- **Onboarding never migrates**: first run adopts existing data at the chosen folder if present, else initializes fresh.
- **Electron owns all data-dir logic**; Ruby receives a resolved `DATA_DIR` via env.
- **Security**: `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true`, single-instance lock.
- Work on a feature branch (e.g. `feat/desktop-app`), not `main`.

---

## File Structure

**Ruby app (repo root) — additive only:**
- Modify `config.ru` — add a `/health` Rack endpoint.
- Create `desktop_boot.rb` — programmatic Puma launcher (works in dev bundle and packaged standalone bundle).
- Create `spec/requests/health_spec.rb` — Rack::Test spec for `/health`.

**Electron layer (`desktop/`):**
- `package.json` — Electron app manifest, `node:test` + build scripts.
- `src/fsutil.js` — reusable fs helpers (list/hash/copy/remove/writable-test).
- `src/settings.js` — `userData/config.json` read/write + session secret.
- `src/data-dir.js` — default path, marker detection, target resolution, initialization.
- `src/migration.js` — `verifyCopy`, `migrate` (copy → verify → delete old).
- `src/server.js` — free-port, spawn Ruby, health poll, graceful stop.
- `src/windows.js` — splash + secure main window.
- `src/dialogs.js` — native onboarding / folder picker / adopt prompt / error.
- `src/menu.js` — application menu with "Data folder…".
- `src/main.js` — orchestration: single-instance, onboarding, boot, quit, change-folder.
- `src/preload.js` — minimal (no privileged bridge).
- `src/splash.html` — boot/migration splash.
- `test/{fsutil,settings,data-dir,migration,server}.test.js` — `node:test` suites.
- `build/stage-ruby-linux.sh` — build relocatable Ruby 3.3.
- `build/vendor-gems.sh` — standalone-vendor production gems against the bundled Ruby.
- `electron-builder.yml` — Linux packaging (AppImage + deb), resource mapping.

---

# Phase A — Milestone 1: working Linux dev app (system Ruby) with the full data-dir feature

## Task 1: `/health` route

**Files:**
- Modify: `config.ru`
- Test: `spec/requests/health_spec.rb`

**Interfaces:**
- Produces: `GET /health` → `200`, body `ok` (used by `server.js#waitForHealth`).

- [ ] **Step 1: Write the failing test**

Create `spec/requests/health_spec.rb`:

```ruby
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Health', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end

  it 'returns 200 ok at /health' do
    get '/health'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq('ok')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/health_spec.rb`
Expected: FAIL (currently `/health` falls through to the `/` app → 302, not 200/"ok").

- [ ] **Step 3: Add the route**

In `config.ru`, add this `map` block immediately **before** the `map '/'` line:

```ruby
map '/health' do
  run ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] }
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/health_spec.rb`
Expected: PASS (1 example, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add config.ru spec/requests/health_spec.rb
git commit -m "feat: add /health endpoint for desktop readiness checks"
```

---

## Task 2: `desktop_boot.rb` Puma launcher

**Files:**
- Create: `desktop_boot.rb`

**Interfaces:**
- Consumes: env `PORT` (required), optional `RACK_ENV`/`DATA_DIR`/`SESSION_SECRET`.
- Produces: a running Puma bound to `tcp://127.0.0.1:$PORT` serving `config.ru`. Spawned by `server.js`.

- [ ] **Step 1: Create the launcher**

Create `desktop_boot.rb`:

```ruby
# Boots the Simply Suite Sinatra app under Puma for the desktop shell.
# Works both in development (Gemfile bundle) and in a packaged app
# (a vendored `--standalone` bundle). Reads PORT from the environment.
ENV['RACK_ENV'] ||= 'production'

standalone = File.join(__dir__, 'vendor', 'bundle', 'bundler', 'setup.rb')
if File.exist?(standalone)
  require_relative 'vendor/bundle/bundler/setup'   # packaged: no bundler needed
else
  require 'bundler/setup'                           # development: use the Gemfile
end

require 'puma/cli'

port = ENV.fetch('PORT')
Puma::CLI.new([
  '-b', "tcp://127.0.0.1:#{port}",
  '-e', 'production',
  '--dir', __dir__               # loads ./config.ru relative to this file
]).run
```

- [ ] **Step 2: Smoke-test it boots and serves `/health` (dev bundle)**

Run (from the repo root):

```bash
PORT=9758 ruby desktop_boot.rb &
BOOT_PID=$!
timeout 20 bash -c 'until curl -sf -o /dev/null http://127.0.0.1:9758/health; do :; done'
curl -s http://127.0.0.1:9758/health; echo
kill $BOOT_PID
```

Expected: prints `ok`.

- [ ] **Step 3: Commit**

```bash
git add desktop_boot.rb
git commit -m "feat: add desktop_boot.rb to launch Puma programmatically"
```

---

## Task 3: Electron project scaffold

**Files:**
- Create: `desktop/package.json`
- Create: `desktop/src/main.js` (temporary; replaced in Task 12)
- Create: `desktop/src/preload.js`

**Interfaces:**
- Produces: an installable Electron app whose `npm start` opens a window. Later tasks replace `main.js`.

- [ ] **Step 1: Create `desktop/package.json`**

```json
{
  "name": "simply-suite-desktop",
  "version": "0.1.0",
  "description": "Desktop shell for Simply Suite",
  "main": "src/main.js",
  "scripts": {
    "start": "electron .",
    "test": "node --test"
  },
  "devDependencies": {
    "electron": "^33.2.0"
  }
}
```

- [ ] **Step 2: Create a minimal `desktop/src/preload.js`**

```js
// Intentionally minimal: no privileged bridge is exposed to the renderer.
// The renderer only ever loads the local Sinatra origin.
```

- [ ] **Step 3: Create a temporary `desktop/src/main.js`**

```js
const { app, BrowserWindow } = require('electron')

app.whenReady().then(() => {
  const win = new BrowserWindow({ width: 900, height: 600 })
  win.loadURL('data:text/html,<h1>Simply Suite desktop shell</h1>')
})

app.on('window-all-closed', () => app.quit())
```

- [ ] **Step 4: Install and launch**

Run:

```bash
cd desktop && npm install
```

Then, on a machine with a display: `npm start` → a window titled with the heading appears. (Headless CI: skip the visual check; `npm install` succeeding is the gate here.)

- [ ] **Step 5: Ignore build artifacts and commit**

Append to `.gitignore`:

```
desktop/node_modules/
desktop/dist/
desktop/vendor/
```

```bash
git add desktop/package.json desktop/src/main.js desktop/src/preload.js .gitignore
git commit -m "chore: scaffold Electron desktop shell"
```

---

## Task 4: `fsutil.js` — filesystem helpers

**Files:**
- Create: `desktop/src/fsutil.js`
- Test: `desktop/test/fsutil.test.js`

**Interfaces:**
- Produces:
  - `listFilesRecursive(root) -> string[]` (relative paths, files only, sorted)
  - `sha256(file) -> string` (hex)
  - `copyTree(src, dest) -> void`
  - `removeTree(dir) -> void`
  - `testWritable(dir) -> boolean`

- [ ] **Step 1: Write the failing test**

Create `desktop/test/fsutil.test.js`:

```js
const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { listFilesRecursive, sha256, copyTree, removeTree, testWritable } = require('../src/fsutil')

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'ss-fsutil-'))

test('listFilesRecursive returns sorted relative file paths', () => {
  const d = tmp()
  fs.mkdirSync(path.join(d, 'a'))
  fs.writeFileSync(path.join(d, 'a', 'x.json'), '1')
  fs.writeFileSync(path.join(d, 'top.txt'), '2')
  assert.deepStrictEqual(listFilesRecursive(d), [path.join('a', 'x.json'), 'top.txt'])
  removeTree(d)
})

test('copyTree reproduces files with identical checksums', () => {
  const src = tmp(); const dest = path.join(tmp(), 'out')
  fs.writeFileSync(path.join(src, 'f.txt'), 'hello')
  copyTree(src, dest)
  assert.strictEqual(sha256(path.join(dest, 'f.txt')), sha256(path.join(src, 'f.txt')))
  removeTree(src); removeTree(dest)
})

test('testWritable: true for a fresh dir, false for an unwritable path', () => {
  const d = tmp()
  assert.strictEqual(testWritable(d), true)
  assert.strictEqual(testWritable('/proc/nonexistent/cannot'), false)
  removeTree(d)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd desktop && node --test test/fsutil.test.js`
Expected: FAIL (`Cannot find module '../src/fsutil'`).

- [ ] **Step 3: Implement `desktop/src/fsutil.js`**

```js
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')

// Relative paths of every file under `root` (files only), sorted.
function listFilesRecursive(root) {
  const out = []
  const walk = (dir) => {
    const entries = fs.readdirSync(dir, { withFileTypes: true })
    for (const e of entries) {
      const abs = path.join(dir, e.name)
      if (e.isDirectory()) walk(abs)
      else if (e.isFile()) out.push(path.relative(root, abs))
    }
  }
  if (fs.existsSync(root)) walk(root)
  return out.sort()
}

// SHA-256 hex of a file's contents.
function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')
}

// Recursively copy the tree at `src` into `dest` (created if absent).
function copyTree(src, dest) {
  fs.mkdirSync(dest, { recursive: true })
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const from = path.join(src, e.name)
    const to = path.join(dest, e.name)
    if (e.isDirectory()) copyTree(from, to)
    else if (e.isFile()) fs.copyFileSync(from, to)
  }
}

// Remove a directory tree if it exists.
function removeTree(dir) {
  fs.rmSync(dir, { recursive: true, force: true })
}

// True if `dir` is writable, proven by creating then deleting a temp file.
function testWritable(dir) {
  try {
    fs.mkdirSync(dir, { recursive: true })
    const probe = path.join(dir, `.write-test-${process.pid}-${Date.now()}`)
    fs.writeFileSync(probe, 'ok')
    fs.unlinkSync(probe)
    return true
  } catch {
    return false
  }
}

module.exports = { listFilesRecursive, sha256, copyTree, removeTree, testWritable }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd desktop && node --test test/fsutil.test.js`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add desktop/src/fsutil.js desktop/test/fsutil.test.js
git commit -m "feat: add fsutil filesystem helpers for the desktop layer"
```

---

## Task 5: `settings.js` — persisted app settings

**Files:**
- Create: `desktop/src/settings.js`
- Test: `desktop/test/settings.test.js`

**Interfaces:**
- Produces:
  - `loadSettings(userDataDir) -> object` (`{}` if missing/corrupt)
  - `saveSettings(userDataDir, settings) -> void` (atomic)
  - `getOrCreateSessionSecret(userDataDir) -> string` (persisted 128-hex)
  - `settingsPath(userDataDir) -> string`

- [ ] **Step 1: Write the failing test**

Create `desktop/test/settings.test.js`:

```js
const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { loadSettings, saveSettings, getOrCreateSessionSecret } = require('../src/settings')

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'ss-settings-'))

test('loadSettings returns {} when nothing is saved', () => {
  assert.deepStrictEqual(loadSettings(tmp()), {})
})

test('saveSettings then loadSettings round-trips', () => {
  const d = tmp()
  saveSettings(d, { dataDir: '/some/path' })
  assert.strictEqual(loadSettings(d).dataDir, '/some/path')
})

test('getOrCreateSessionSecret is stable across calls', () => {
  const d = tmp()
  const a = getOrCreateSessionSecret(d)
  const b = getOrCreateSessionSecret(d)
  assert.strictEqual(a, b)
  assert.match(a, /^[0-9a-f]{128}$/)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd desktop && node --test test/settings.test.js`
Expected: FAIL (`Cannot find module '../src/settings'`).

- [ ] **Step 3: Implement `desktop/src/settings.js`**

```js
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')

function settingsPath(userDataDir) {
  return path.join(userDataDir, 'config.json')
}

// Read settings; returns {} if the file is missing, unreadable, or corrupt.
function loadSettings(userDataDir) {
  try {
    return JSON.parse(fs.readFileSync(settingsPath(userDataDir), 'utf8'))
  } catch {
    return {}
  }
}

// Persist settings atomically (temp file + rename).
function saveSettings(userDataDir, settings) {
  fs.mkdirSync(userDataDir, { recursive: true })
  const file = settingsPath(userDataDir)
  const tmp = `${file}.tmp-${process.pid}`
  fs.writeFileSync(tmp, JSON.stringify(settings, null, 2))
  fs.renameSync(tmp, file)
}

// Return the persisted session secret, generating and saving one on first use.
function getOrCreateSessionSecret(userDataDir) {
  const s = loadSettings(userDataDir)
  if (s.sessionSecret) return s.sessionSecret
  s.sessionSecret = crypto.randomBytes(64).toString('hex')
  saveSettings(userDataDir, s)
  return s.sessionSecret
}

module.exports = { settingsPath, loadSettings, saveSettings, getOrCreateSessionSecret }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd desktop && node --test test/settings.test.js`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add desktop/src/settings.js desktop/test/settings.test.js
git commit -m "feat: add persisted settings store (data dir + session secret)"
```

---

## Task 6: `data-dir.js` — location resolution & marker

**Files:**
- Create: `desktop/src/data-dir.js`
- Test: `desktop/test/data-dir.test.js`

**Interfaces:**
- Produces:
  - `MARKER = '.simply-suite.json'`, `DATA_SUBFOLDER = 'Simply Suite'`
  - `defaultDataDir(userDataDir) -> string` (`<userDataDir>/data`)
  - `isDataFolder(dir) -> boolean` (marker present)
  - `resolveTarget(pickedDir) -> string` (in place if marker, else `<picked>/Simply Suite`)
  - `initializeDataFolder(dir) -> string` (mkdir + write marker)

- [ ] **Step 1: Write the failing test**

Create `desktop/test/data-dir.test.js`:

```js
const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { defaultDataDir, isDataFolder, resolveTarget, initializeDataFolder, DATA_SUBFOLDER, MARKER } = require('../src/data-dir')

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'ss-datadir-'))

test('defaultDataDir nests a data/ folder under userData', () => {
  assert.strictEqual(defaultDataDir('/u/x'), path.join('/u/x', 'data'))
})

test('initializeDataFolder writes the marker and isDataFolder detects it', () => {
  const d = path.join(tmp(), 'store')
  initializeDataFolder(d)
  assert.ok(fs.existsSync(path.join(d, MARKER)))
  assert.strictEqual(isDataFolder(d), true)
})

test('resolveTarget nests a subfolder for a plain parent, uses SS folder in place', () => {
  const parent = tmp()
  assert.strictEqual(resolveTarget(parent), path.join(parent, DATA_SUBFOLDER))
  const existing = path.join(tmp(), 'store')
  initializeDataFolder(existing)
  assert.strictEqual(resolveTarget(existing), existing)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd desktop && node --test test/data-dir.test.js`
Expected: FAIL (`Cannot find module '../src/data-dir'`).

- [ ] **Step 3: Implement `desktop/src/data-dir.js`**

```js
const fs = require('fs')
const path = require('path')

const MARKER = '.simply-suite.json'
const DATA_SUBFOLDER = 'Simply Suite'

// Default data folder: a dedicated subfolder inside Electron's userData dir.
function defaultDataDir(userDataDir) {
  return path.join(userDataDir, 'data')
}

// True if `dir` already carries the Simply Suite marker.
function isDataFolder(dir) {
  return fs.existsSync(path.join(dir, MARKER))
}

// Decide the actual data folder for a folder the user picked: if they pointed
// straight at an existing SS folder, use it in place; otherwise nest a
// dedicated "Simply Suite" subfolder so we never own their whole parent folder.
function resolveTarget(pickedDir) {
  return isDataFolder(pickedDir) ? pickedDir : path.join(pickedDir, DATA_SUBFOLDER)
}

// Ensure the folder exists and carries the marker. Returns `dir`.
function initializeDataFolder(dir) {
  fs.mkdirSync(dir, { recursive: true })
  const marker = path.join(dir, MARKER)
  if (!fs.existsSync(marker)) {
    fs.writeFileSync(marker, JSON.stringify({ app: 'simply-suite', schema: 1 }, null, 2))
  }
  return dir
}

module.exports = { MARKER, DATA_SUBFOLDER, defaultDataDir, isDataFolder, resolveTarget, initializeDataFolder }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd desktop && node --test test/data-dir.test.js`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add desktop/src/data-dir.js desktop/test/data-dir.test.js
git commit -m "feat: add data-dir resolution and marker handling"
```

---

## Task 7: `migration.js` — checksum-verified move

**Files:**
- Create: `desktop/src/migration.js`
- Test: `desktop/test/migration.test.js`

**Interfaces:**
- Consumes: `fsutil` (`listFilesRecursive`, `sha256`, `copyTree`, `removeTree`).
- Produces:
  - `verifyCopy(src, dest) -> { ok: boolean, reason?: string }`
  - `migrate(oldDir, newDir) -> void` (copy → verify → delete old; throws on failure with old left intact)

- [ ] **Step 1: Write the failing test**

Create `desktop/test/migration.test.js`:

```js
const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { verifyCopy, migrate } = require('../src/migration')

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'ss-migrate-'))

test('verifyCopy: ok for an identical tree, not-ok for a mutated file', () => {
  const a = tmp(); const b = tmp()
  fs.writeFileSync(path.join(a, 'f.txt'), 'data')
  fs.writeFileSync(path.join(b, 'f.txt'), 'data')
  assert.deepStrictEqual(verifyCopy(a, b), { ok: true })
  fs.writeFileSync(path.join(b, 'f.txt'), 'DATA')
  assert.strictEqual(verifyCopy(a, b).ok, false)
})

test('migrate copies data to newDir and removes oldDir', () => {
  const old = tmp(); const parent = tmp()
  const nw = path.join(parent, 'Simply Suite')
  fs.mkdirSync(path.join(old, 'invoices'), { recursive: true })
  fs.writeFileSync(path.join(old, 'invoices', 'a.json'), '{"n":1}')
  migrate(old, nw)
  assert.strictEqual(fs.existsSync(old), false)
  assert.strictEqual(fs.readFileSync(path.join(nw, 'invoices', 'a.json'), 'utf8'), '{"n":1}')
})

test('migrate throws and preserves oldDir when the destination cannot be written', () => {
  const old = tmp()
  fs.writeFileSync(path.join(old, 'f.txt'), 'x')
  // A file where the destination directory should go → copyTree mkdir fails.
  const clash = path.join(tmp(), 'blocker')
  fs.writeFileSync(clash, 'i am a file, not a dir')
  const dest = path.join(clash, 'inside')
  assert.throws(() => migrate(old, dest))
  assert.strictEqual(fs.existsSync(path.join(old, 'f.txt')), true)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd desktop && node --test test/migration.test.js`
Expected: FAIL (`Cannot find module '../src/migration'`).

- [ ] **Step 3: Implement `desktop/src/migration.js`**

```js
const fs = require('fs')
const path = require('path')
const { listFilesRecursive, sha256, copyTree, removeTree } = require('./fsutil')

// Verify `dest` is a byte-for-byte copy of `src`: same relative file set, each
// with matching size and SHA-256. Returns { ok, reason? }.
function verifyCopy(src, dest) {
  const a = listFilesRecursive(src)
  const b = listFilesRecursive(dest)
  if (a.length !== b.length || a.some((f, i) => f !== b[i])) {
    return { ok: false, reason: 'file set differs' }
  }
  for (const rel of a) {
    const fa = path.join(src, rel)
    const fb = path.join(dest, rel)
    if (fs.statSync(fa).size !== fs.statSync(fb).size) return { ok: false, reason: `size differs: ${rel}` }
    if (sha256(fa) !== sha256(fb)) return { ok: false, reason: `checksum differs: ${rel}` }
  }
  return { ok: true }
}

// Move data from oldDir to newDir with verification. Copies, verifies
// byte-for-byte, and ONLY THEN deletes oldDir. On any failure the partial
// newDir is removed and oldDir is left intact; the error is re-thrown so the
// caller can keep running on oldDir. Precondition: newDir is empty/new
// (adopt/conflict cases are resolved by the caller).
function migrate(oldDir, newDir) {
  try {
    copyTree(oldDir, newDir)
  } catch (e) {
    removeTree(newDir)
    throw new Error(`copy failed: ${e.message}`)
  }
  const result = verifyCopy(oldDir, newDir)
  if (!result.ok) {
    removeTree(newDir)
    throw new Error(`verification failed: ${result.reason}`)
  }
  removeTree(oldDir)
}

module.exports = { verifyCopy, migrate }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd desktop && node --test test/migration.test.js`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add desktop/src/migration.js desktop/test/migration.test.js
git commit -m "feat: add checksum-verified data-folder migration"
```

---

## Task 8: `server.js` — Ruby process supervisor

**Files:**
- Create: `desktop/src/server.js`
- Test: `desktop/test/server.test.js`

**Interfaces:**
- Produces:
  - `pickFreePort() -> Promise<number>`
  - `rubyLauncher(appDir) -> { cmd, args }` (dev default: `bundle exec ruby desktop_boot.rb`)
  - `startServer({ appDir, dataDir, sessionSecret, port, logStream?, launcher? }) -> ChildProcess`
  - `waitForHealth(port, { timeoutMs?, intervalMs? }) -> Promise<void>`
  - `stopServer(child) -> Promise<void>`
- Note: this module must NOT `require('electron')` — it stays plain-Node testable. The packaged launcher is injected by `main.js`.

- [ ] **Step 1: Write the failing test**

Create `desktop/test/server.test.js`:

```js
const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { pickFreePort, startServer, waitForHealth, stopServer } = require('../src/server')

const APP_DIR = path.resolve(__dirname, '..', '..') // repo root

test('pickFreePort resolves a positive integer', async () => {
  const p = await pickFreePort()
  assert.ok(Number.isInteger(p) && p > 0)
})

test('server boots, answers /health, and stops', async () => {
  const port = await pickFreePort()
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ss-serv-'))
  const child = startServer({ appDir: APP_DIR, dataDir, sessionSecret: 'test-secret', port })
  try {
    await waitForHealth(port, { timeoutMs: 30000 })
  } finally {
    await stopServer(child)
    fs.rmSync(dataDir, { recursive: true, force: true })
  }
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd desktop && node --test test/server.test.js`
Expected: FAIL (`Cannot find module '../src/server'`).

- [ ] **Step 3: Implement `desktop/src/server.js`**

```js
const net = require('net')
const http = require('http')
const path = require('path')
const { spawn } = require('child_process')

// Resolve a free TCP port on the loopback interface.
function pickFreePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer()
    srv.unref()
    srv.on('error', reject)
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address()
      srv.close(() => resolve(port))
    })
  })
}

// Argv to launch the Ruby server in development (through Bundler).
// The packaged app injects a different launcher (bundled Ruby) via startServer.
function rubyLauncher(appDir) {
  return { cmd: 'bundle', args: ['exec', 'ruby', path.join(appDir, 'desktop_boot.rb')] }
}

// Spawn the Ruby/Puma server. Returns the ChildProcess.
function startServer({ appDir, dataDir, sessionSecret, port, logStream, launcher = rubyLauncher }) {
  const { cmd, args } = launcher(appDir)
  const child = spawn(cmd, args, {
    cwd: appDir,
    env: {
      ...process.env,
      PORT: String(port),
      DATA_DIR: dataDir,
      SESSION_SECRET: sessionSecret,
      RACK_ENV: 'production'
    }
  })
  if (logStream) {
    child.stdout.pipe(logStream)
    child.stderr.pipe(logStream)
  }
  return child
}

// Poll GET /health until 200 or the timeout elapses.
function waitForHealth(port, { timeoutMs = 30000, intervalMs = 200 } = {}) {
  const deadline = Date.now() + timeoutMs
  return new Promise((resolve, reject) => {
    const retry = () => {
      if (Date.now() > deadline) return reject(new Error('server did not become healthy in time'))
      setTimeout(tick, intervalMs)
    }
    const tick = () => {
      const req = http.get({ host: '127.0.0.1', port, path: '/health', timeout: 1000 }, (res) => {
        res.resume()
        if (res.statusCode === 200) resolve()
        else retry()
      })
      req.on('error', retry)
      req.on('timeout', () => { req.destroy(); retry() })
    }
    tick()
  })
}

// Gracefully stop the server child (SIGTERM, then SIGKILL after a grace period).
function stopServer(child) {
  return new Promise((resolve) => {
    if (!child || child.exitCode !== null || child.signalCode !== null) return resolve()
    let done = false
    const finish = () => { if (!done) { done = true; resolve() } }
    child.once('exit', finish)
    if (process.platform === 'win32') {
      spawn('taskkill', ['/pid', String(child.pid), '/T', '/F'])
    } else {
      child.kill('SIGTERM')
      setTimeout(() => { if (!done) child.kill('SIGKILL') }, 5000)
    }
  })
}

module.exports = { pickFreePort, rubyLauncher, startServer, waitForHealth, stopServer }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd desktop && node --test test/server.test.js`
Expected: PASS (2 tests; the boot test really spawns Puma, so allow ~5–10s).

- [ ] **Step 5: Commit**

```bash
git add desktop/src/server.js desktop/test/server.test.js
git commit -m "feat: add Ruby server supervisor (port, spawn, health, stop)"
```

---

## Task 9: `windows.js` + `splash.html`

**Files:**
- Create: `desktop/src/windows.js`
- Create: `desktop/src/splash.html`

**Interfaces:**
- Produces:
  - `createSplash() -> BrowserWindow`
  - `closeSplash() -> void`
  - `createMainWindow(url) -> BrowserWindow` (secure webPreferences; shows on `ready-to-show`)
- Note: Electron-only module; verified by `node --check` here and exercised at Task 12.

- [ ] **Step 1: Create `desktop/src/splash.html`**

```html
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <style>
      body { font-family: system-ui, sans-serif; display: flex; align-items: center;
             justify-content: center; height: 100vh; margin: 0; background: #111; color: #eee; }
      .box { text-align: center }
      .spinner { margin: 12px auto 0; width: 22px; height: 22px; border: 3px solid #555;
                 border-top-color: #eee; border-radius: 50%; animation: spin 0.9s linear infinite; }
      @keyframes spin { to { transform: rotate(360deg) } }
    </style>
  </head>
  <body>
    <div class="box">
      <div>Starting Simply Suite…</div>
      <div class="spinner"></div>
    </div>
  </body>
</html>
```

- [ ] **Step 2: Implement `desktop/src/windows.js`**

```js
const { BrowserWindow } = require('electron')
const path = require('path')

let splash = null

function createSplash() {
  splash = new BrowserWindow({
    width: 420, height: 260, frame: false, resizable: false, show: true,
    webPreferences: { contextIsolation: true, nodeIntegration: false }
  })
  splash.loadFile(path.join(__dirname, 'splash.html'))
  return splash
}

function closeSplash() {
  if (splash && !splash.isDestroyed()) splash.close()
  splash = null
}

function createMainWindow(url) {
  const win = new BrowserWindow({
    width: 1280, height: 860, show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })
  win.once('ready-to-show', () => win.show())
  win.loadURL(url)
  return win
}

module.exports = { createSplash, closeSplash, createMainWindow }
```

- [ ] **Step 3: Syntax-check the module**

Run: `cd desktop && node --check src/windows.js`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add desktop/src/windows.js desktop/src/splash.html
git commit -m "feat: add splash and secure main window helpers"
```

---

## Task 10: `dialogs.js` — native onboarding & prompts

**Files:**
- Create: `desktop/src/dialogs.js`

**Interfaces:**
- Consumes: `data-dir` (`resolveTarget`).
- Produces:
  - `runOnboarding(defaultDir) -> Promise<string|null>` (resolved data dir, or null to quit)
  - `chooseFolder(title) -> Promise<string|null>`
  - `confirmAdopt(newDir) -> Promise<boolean>`
  - `showErrorBox(title, message) -> void`

- [ ] **Step 1: Implement `desktop/src/dialogs.js`**

```js
const { dialog } = require('electron')
const { resolveTarget } = require('./data-dir')

// First-run onboarding. Returns the resolved data-folder path, or null to quit.
async function runOnboarding(defaultDir) {
  const { response } = await dialog.showMessageBox({
    type: 'question',
    buttons: ['Use default location', 'Choose a folder…', 'Quit'],
    defaultId: 0, cancelId: 2,
    title: 'Simply Suite',
    message: 'Where should Simply Suite store your data?',
    detail: `Default location:\n${defaultDir}`
  })
  if (response === 0) return defaultDir
  if (response === 2) return null
  const picked = await chooseFolder('Choose a folder for Simply Suite data')
  return picked ? resolveTarget(picked) : null
}

// Native folder picker. Returns the selected path or null.
async function chooseFolder(title) {
  const { canceled, filePaths } = await dialog.showOpenDialog({
    title: title || 'Choose a folder',
    properties: ['openDirectory', 'createDirectory']
  })
  return canceled || !filePaths.length ? null : filePaths[0]
}

// Ask whether to adopt existing data at newDir. Returns true to adopt.
async function confirmAdopt(newDir) {
  const { response } = await dialog.showMessageBox({
    type: 'warning',
    buttons: ['Adopt existing data', 'Cancel'],
    defaultId: 0, cancelId: 1,
    title: 'Existing data found',
    message: 'That folder already contains Simply Suite data.',
    detail: `Switch to the data already in:\n${newDir}\n\nYour current data is left where it is — not copied, not deleted.`
  })
  return response === 0
}

function showErrorBox(title, message) {
  dialog.showErrorBox(title, message)
}

module.exports = { runOnboarding, chooseFolder, confirmAdopt, showErrorBox }
```

- [ ] **Step 2: Syntax-check the module**

Run: `cd desktop && node --check src/dialogs.js`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add desktop/src/dialogs.js
git commit -m "feat: add native onboarding and data-folder dialogs"
```

---

## Task 11: `menu.js` — application menu

**Files:**
- Create: `desktop/src/menu.js`

**Interfaces:**
- Produces: `buildMenu({ onChangeDataFolder }) -> void` (installs the app menu; File → "Data folder…" invokes the handler).

- [ ] **Step 1: Implement `desktop/src/menu.js`**

```js
const { Menu } = require('electron')

// Build and install the application menu. `handlers.onChangeDataFolder` runs
// when the user chooses File → Data folder…
function buildMenu(handlers) {
  const isMac = process.platform === 'darwin'
  const template = [
    ...(isMac ? [{ role: 'appMenu' }] : []),
    {
      label: 'File',
      submenu: [
        { label: 'Data folder…', click: () => handlers.onChangeDataFolder() },
        { type: 'separator' },
        isMac ? { role: 'close' } : { role: 'quit' }
      ]
    },
    { role: 'editMenu' },
    { role: 'viewMenu' },
    { role: 'windowMenu' }
  ]
  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}

module.exports = { buildMenu }
```

- [ ] **Step 2: Syntax-check the module**

Run: `cd desktop && node --check src/menu.js`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add desktop/src/menu.js
git commit -m "feat: add application menu with Data folder entry"
```

---

## Task 12: `main.js` — orchestration & first-run flow

**Files:**
- Modify (replace): `desktop/src/main.js`

**Interfaces:**
- Consumes: `settings`, `data-dir`, `server`, `windows`, `dialogs`, `menu`.
- Produces: a runnable app — single-instance, first-run onboarding, boot server, main window, graceful quit. The change-folder handler is stubbed here and completed in Task 13.

- [ ] **Step 1: Replace `desktop/src/main.js`**

```js
const { app } = require('electron')
const path = require('path')
const fs = require('fs')
const { loadSettings, saveSettings, getOrCreateSessionSecret } = require('./settings')
const { defaultDataDir, initializeDataFolder } = require('./data-dir')
const { pickFreePort, rubyLauncher, startServer, waitForHealth, stopServer } = require('./server')
const { createSplash, closeSplash, createMainWindow } = require('./windows')
const { runOnboarding, showErrorBox } = require('./dialogs')
const { buildMenu } = require('./menu')

// Where the Ruby app lives: bundled under resources/app when packaged,
// otherwise the repo root (two levels up from desktop/src).
const APP_DIR = app.isPackaged
  ? path.join(process.resourcesPath, 'app')
  : path.resolve(__dirname, '..', '..')

let serverChild = null
let mainWindow = null
let currentDataDir = null
let isQuitting = false

// Choose the Ruby launcher: bundled Ruby when packaged, Bundler in dev.
function launcher(appDir) {
  if (app.isPackaged) {
    return {
      cmd: path.join(process.resourcesPath, 'ruby', 'bin', 'ruby'),
      args: [path.join(appDir, 'desktop_boot.rb')]
    }
  }
  return rubyLauncher(appDir)
}

function serverLog() {
  const dir = path.join(app.getPath('userData'), 'logs')
  fs.mkdirSync(dir, { recursive: true })
  return fs.createWriteStream(path.join(dir, 'server.log'), { flags: 'a' })
}

// Boot the Ruby server against `dataDir`; returns its base URL.
async function bootServer(dataDir) {
  const sessionSecret = getOrCreateSessionSecret(app.getPath('userData'))
  const port = await pickFreePort()
  serverChild = startServer({ appDir: APP_DIR, dataDir, sessionSecret, port, logStream: serverLog(), launcher })
  await waitForHealth(port)
  currentDataDir = dataDir
  return `http://127.0.0.1:${port}/`
}

// Resolve the data folder: use the saved one, or run first-run onboarding.
async function resolveDataDir() {
  const userData = app.getPath('userData')
  const settings = loadSettings(userData)
  if (settings.dataDir) return settings.dataDir

  const chosen = await runOnboarding(defaultDataDir(userData))
  if (!chosen) { app.quit(); return null }
  initializeDataFolder(chosen)
  saveSettings(userData, { ...settings, dataDir: chosen })
  return chosen
}

async function start() {
  const dataDir = await resolveDataDir()
  if (!dataDir) return
  createSplash()
  try {
    const url = await bootServer(dataDir)
    mainWindow = createMainWindow(url)
  } catch (e) {
    showErrorBox('Simply Suite failed to start', String((e && e.message) || e))
    app.quit()
    return
  } finally {
    closeSplash()
  }
  buildMenu({ onChangeDataFolder: () => {} }) // completed in Task 13
}

async function gracefulQuit() {
  if (isQuitting) return
  isQuitting = true
  await stopServer(serverChild)
  serverChild = null
  app.quit()
}

if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore()
      mainWindow.focus()
    }
  })
  app.whenReady().then(start)
}

app.on('window-all-closed', gracefulQuit)
app.on('before-quit', (e) => {
  if (isQuitting || !serverChild) return
  e.preventDefault()
  gracefulQuit()
})
```

- [ ] **Step 2: Syntax-check**

Run: `cd desktop && node --check src/main.js`
Expected: no output, exit 0.

- [ ] **Step 3: Manual run — first launch**

Run: `cd desktop && npm start`
Expected sequence:
1. Onboarding dialog appears → click **Use default location**.
2. Splash shows briefly, then the Simply Suite dashboard loads in the window.
3. `ls "$(node -e "console.log(require('electron'))" 2>/dev/null || true)"` — instead verify data landed: the folder `~/.config/Simply Suite/data/` exists and contains `.simply-suite.json`.

Verify data location:

```bash
ls -la ~/.config/"Simply Suite"/data/
```

Expected: contains `.simply-suite.json` (and entity folders once you create a business).

- [ ] **Step 4: Manual run — second launch skips onboarding**

Run `npm start` again.
Expected: no onboarding dialog (saved `dataDir` is reused); the app boots straight to the dashboard.

- [ ] **Step 5: Verify clean shutdown**

Close the window, then:

```bash
pgrep -af 'desktop_boot.rb|puma' || echo "no orphan server processes"
```

Expected: `no orphan server processes`.

- [ ] **Step 6: Commit**

```bash
git add desktop/src/main.js
git commit -m "feat: orchestrate desktop boot, onboarding, and lifecycle"
```

---

## Task 13: Change-data-folder flow (migrate / adopt / conflict)

**Files:**
- Modify: `desktop/src/main.js`

**Interfaces:**
- Consumes: `migration.migrate`, `data-dir` (`isDataFolder`, `resolveTarget`, `initializeDataFolder`), `dialogs` (`chooseFolder`, `confirmAdopt`), `fsutil.testWritable`.
- Produces: `changeDataFolder()` wired to the menu's `onChangeDataFolder`.

- [ ] **Step 1: Extend the imports in `desktop/src/main.js`**

Replace the existing `data-dir`, `dialogs`, and `server`/`fsutil` import lines' region by adding the extra names. The import block should read:

```js
const { defaultDataDir, initializeDataFolder, isDataFolder, resolveTarget } = require('./data-dir')
const { runOnboarding, chooseFolder, confirmAdopt, showErrorBox } = require('./dialogs')
const { migrate } = require('./migration')
const { testWritable } = require('./fsutil')
```

(Leave the `settings`, `server`, `windows`, `menu` imports unchanged.)

- [ ] **Step 2: Add the `changeDataFolder` function** (above the single-instance block)

```js
// Change the data folder from the menu: pick → write-test → conflict check →
// stop server → migrate (or adopt) → save → restart. Fail-safe: on migrate
// failure the old data is untouched and the app restarts on it.
async function changeDataFolder() {
  const picked = await chooseFolder('Choose a new folder for Simply Suite data')
  if (!picked) return
  const newDir = resolveTarget(picked)
  if (path.resolve(newDir) === path.resolve(currentDataDir)) return

  if (!testWritable(newDir)) {
    showErrorBox('Cannot use that folder', `Simply Suite can't write to:\n${newDir}`)
    return
  }

  const adoptExisting = isDataFolder(newDir)
  if (adoptExisting && !(await confirmAdopt(newDir))) return

  const oldDir = currentDataDir
  createSplash()
  if (mainWindow) mainWindow.hide()
  await stopServer(serverChild)
  serverChild = null

  let dataDir = oldDir
  try {
    if (adoptExisting) {
      dataDir = newDir                 // switch only; leave old data in place
    } else {
      initializeDataFolder(newDir)
      migrate(oldDir, newDir)          // copy → verify → delete old
      dataDir = newDir
    }
    saveSettings(app.getPath('userData'), { ...loadSettings(app.getPath('userData')), dataDir })
  } catch (e) {
    dataDir = oldDir                    // migrate failed before deleting → old intact
    showErrorBox('Data move failed', `${(e && e.message) || e}\n\nYour data was left in its original location.`)
  }

  try {
    const url = await bootServer(dataDir)
    if (mainWindow) mainWindow.loadURL(url)
  } catch (e) {
    showErrorBox('Simply Suite failed to restart', String((e && e.message) || e))
    app.quit()
    return
  } finally {
    if (mainWindow) mainWindow.show()
    closeSplash()
  }
}
```

- [ ] **Step 3: Wire the menu handler**

Change the `buildMenu` call in `start()` from:

```js
  buildMenu({ onChangeDataFolder: () => {} }) // completed in Task 13
```

to:

```js
  buildMenu({ onChangeDataFolder: changeDataFolder })
```

- [ ] **Step 4: Syntax-check**

Run: `cd desktop && node --check src/main.js`
Expected: no output, exit 0.

- [ ] **Step 5: Manual run — migrate to an empty folder**

1. `cd desktop && npm start`; in the app create a business (so there's data).
2. Menu **File → Data folder…** → pick an **empty** folder, e.g. `~/ss-move-test`.
3. Expected: brief splash, app reloads, your business is still there.
4. Verify:

```bash
ls -la ~/ss-move-test/"Simply Suite"/           # marker + entity folders present
ls -la ~/.config/"Simply Suite"/data/ 2>/dev/null || echo "old data folder removed"
```

Expected: new folder has the data; old `data/` folder is gone.

- [ ] **Step 6: Manual run — adopt existing data**

1. With the app now on `~/ss-move-test`, Menu **File → Data folder…** → pick `~/ss-move-test` again (or its `Simply Suite` subfolder).
2. Expected: "Existing data found" prompt → **Adopt existing data** → app reloads on that data; no copy, old location (if different) left intact.

- [ ] **Step 7: Commit**

```bash
git add desktop/src/main.js
git commit -m "feat: change data folder with verified migration and adopt flow"
```

---

**End of Phase A.** You now have a working Linux desktop app (running the system Ruby via Bundler) with onboarding and a safe, configurable data directory.

---

# Phase B — Milestone 2: self-contained, offline Linux app

## Task 14: Build a relocatable Ruby 3.3

**Files:**
- Create: `desktop/build/stage-ruby-linux.sh`

**Interfaces:**
- Produces: `desktop/vendor/ruby-linux/bin/ruby` — a relocatable Ruby 3.3 with Bundler installed. Consumed by Task 15 and by the packaged launcher.

- [ ] **Step 1: Create `desktop/build/stage-ruby-linux.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

RUBY_VERSION="${RUBY_VERSION:-3.3.11}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/../vendor/ruby-linux"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "Building relocatable Ruby $RUBY_VERSION -> $DEST"
curl -fsSL "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.gz" -o "$BUILD/ruby.tar.gz"
tar -xzf "$BUILD/ruby.tar.gz" -C "$BUILD"
cd "$BUILD/ruby-${RUBY_VERSION}"

# --disable-shared: statically link libruby into the binary => fully relocatable
# --enable-load-relative: locate the stdlib relative to the executable
./configure --prefix="$DEST" --disable-shared --enable-load-relative --disable-install-doc
make -j"$(nproc)"
rm -rf "$DEST"
make install

"$DEST/bin/ruby" -v
"$DEST/bin/gem" install bundler --no-document
echo "Bundled Ruby ready."
```

- [ ] **Step 2: Build it**

Run: `cd desktop && bash build/stage-ruby-linux.sh`
Expected (takes several minutes): ends with `Bundled Ruby ready.`

- [ ] **Step 3: Verify it runs relocated**

Run:

```bash
cd desktop && ./vendor/ruby-linux/bin/ruby -e "puts RUBY_VERSION"
```

Expected: `3.3.11` (or the pinned version).

- [ ] **Step 4: Commit the script** (the built runtime stays gitignored via `desktop/vendor/`)

```bash
git add desktop/build/stage-ruby-linux.sh
git commit -m "build: script to build a relocatable Ruby 3.3 for Linux"
```

---

## Task 15: Vendor production gems (standalone) against the bundled Ruby

**Files:**
- Create: `desktop/build/vendor-gems.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `vendor/bundle/bundler/setup.rb` at the repo root (standalone bundle of production gems, native extensions compiled against the bundled Ruby). Consumed by `desktop_boot.rb`'s packaged path.

- [ ] **Step 1: Create `desktop/build/vendor-gems.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"          # repo root
RUBY_DIR="$HERE/../vendor/ruby-linux"

if [ ! -x "$RUBY_DIR/bin/ruby" ]; then
  echo "Bundled Ruby not found — run build/stage-ruby-linux.sh first." >&2
  exit 1
fi

export PATH="$RUBY_DIR/bin:$PATH"
cd "$ROOT"
echo "Vendoring production gems with $(ruby -v)"
bundle config set --local path 'vendor/bundle'
bundle config set --local without 'development test'
bundle install --standalone

test -f vendor/bundle/bundler/setup.rb && echo "Standalone bundle ready."
```

- [ ] **Step 2: Vendor the gems**

Run: `cd desktop && bash build/vendor-gems.sh`
Expected: ends with `Standalone bundle ready.`

- [ ] **Step 3: Smoke-test the packaged boot path with the bundled Ruby**

Run (from the repo root):

```bash
PORT=9759 DATA_DIR=/tmp/ss-bundle-test desktop/vendor/ruby-linux/bin/ruby desktop_boot.rb &
BOOT_PID=$!
timeout 30 bash -c 'until curl -sf -o /dev/null http://127.0.0.1:9759/health; do :; done'
curl -s http://127.0.0.1:9759/health; echo
kill $BOOT_PID
```

Expected: prints `ok` (proves the bundled Ruby + standalone bundle + native gems boot Puma). This exercises `desktop_boot.rb`'s `File.exist?(standalone)` branch.

- [ ] **Step 4: Ignore the vendored bundle and commit the script**

Append to `.gitignore`:

```
/vendor/bundle/
/.bundle/
```

```bash
git add desktop/build/vendor-gems.sh .gitignore
git commit -m "build: script to vendor standalone production gems"
```

---

## Task 16: Package AppImage + deb with electron-builder

**Files:**
- Modify: `desktop/package.json`
- Create: `desktop/electron-builder.yml`

**Interfaces:**
- Produces: `desktop/dist/Simply Suite-<ver>.AppImage` and a `.deb`, bundling `resources/app` (Ruby app + standalone gems) and `resources/ruby` (relocatable Ruby). Consumes the packaged launcher already in `main.js` (`process.resourcesPath/ruby/bin/ruby` + `resources/app/desktop_boot.rb`).

- [ ] **Step 1: Add electron-builder to `desktop/package.json`**

Update the file to:

```json
{
  "name": "simply-suite-desktop",
  "version": "0.1.0",
  "description": "Desktop shell for Simply Suite",
  "main": "src/main.js",
  "scripts": {
    "start": "electron .",
    "test": "node --test",
    "build:ruby": "bash build/stage-ruby-linux.sh",
    "build:gems": "bash build/vendor-gems.sh",
    "dist": "electron-builder"
  },
  "devDependencies": {
    "electron": "^33.2.0",
    "electron-builder": "^25.1.8"
  }
}
```

- [ ] **Step 2: Create `desktop/electron-builder.yml`**

```yaml
appId: co.doublenot.simply-suite
productName: Simply Suite
directories:
  output: dist
files:
  - src/**/*
  - package.json
extraResources:
  # The Ruby app (source + standalone vendored gems) → resources/app
  - from: ../
    to: app
    filter:
      - "**/*"
      - "!desktop/**"
      - "!.git/**"
      - "!spec/**"
      - "!docs/**"
      - "!data/**"
      - "!dist/**"
      - "!node_modules/**"
      - "!tailwindcss"
  # The relocatable Ruby runtime → resources/ruby
  - from: vendor/ruby-linux
    to: ruby
linux:
  target:
    - AppImage
    - deb
  category: Office
```

- [ ] **Step 3: Install electron-builder**

Run: `cd desktop && npm install`
Expected: `electron-builder` added to `node_modules`.

- [ ] **Step 4: Build the installers** (requires Tasks 14 & 15 artifacts present)

Run:

```bash
cd desktop
npm run build:ruby     # if not already built
npm run build:gems     # if not already vendored
npm run dist
```

Expected: `dist/Simply Suite-0.1.0.AppImage` and a `.deb` are produced.

- [ ] **Step 5: Run the AppImage and verify it is self-contained**

Run:

```bash
cd desktop
chmod +x "dist/Simply Suite-0.1.0.AppImage"
"./dist/Simply Suite-0.1.0.AppImage"
```

Expected: onboarding → dashboard loads. Confirm it used the **bundled** Ruby (not system Bundler):

```bash
grep -i "ruby version" ~/.config/"Simply Suite"/logs/server.log | tail -1
```

Expected: the Puma boot line naming Ruby 3.3.x from the bundled runtime. Also confirm offline operation by disabling networking and relaunching — the app still works.

- [ ] **Step 6: Commit**

```bash
git add desktop/package.json desktop/electron-builder.yml
git commit -m "build: package Simply Suite as a Linux AppImage and deb"
```

---

**End of Phase B.** You now have a self-contained, offline Linux installer that carries its own Ruby runtime — no Ruby required on the target machine.

---

## Self-Review (author checklist — completed)

**Spec coverage (Linux scope):**
- §3.1 launch lifecycle → Tasks 8, 12. §3.2 single-instance → Task 12. §3.3 security → Task 9 (webPreferences), Task 8/12 (loopback). §3.4 data location/settings/marker → Tasks 5, 6, 12. §3.5 onboarding → Tasks 10, 12. §3.6 migration → Tasks 7, 13. §4 embedded Ruby → Tasks 2, 14, 15, 16. §5 Ruby app changes → Tasks 1, 2. §7 packaging (Linux) → Task 16. §13 tests → Tasks 4–8 (unit/integration) + manual steps in 12, 13, 16.
- **Deferred to follow-up plans (out of this plan's scope):** §4.3 macOS/Windows runtimes, §8 signing/notarization, §9 CI matrix.

**Placeholder scan:** No TBD/TODO; every code step shows complete code; the one stub (`onChangeDataFolder: () => {}`) is explicitly introduced in Task 12 and replaced in Task 13.

**Type/name consistency:** `launcher` option threads `server.js` → `main.js`; `currentDataDir`, `bootServer`, `serverChild`, `mainWindow` consistent across Tasks 12–13; `resolveTarget`/`isDataFolder`/`initializeDataFolder`/`migrate`/`testWritable` signatures match their defining tasks.

---

## Follow-up plans (separate specs/plans — not tasked here)

These require environments/accounts unavailable on this Linux machine and should each become their own plan producing a testable artifact:

1. **macOS** — `build/stage-ruby-macos.sh` (arm64 + x64 relocatable Ruby), `.dmg` target, `afterSign` notarization (needs Apple Developer ID, $99/yr). Build/verify on a Mac.
2. **Windows** — RubyInstaller-based bundled runtime, NSIS target, optional code-signing cert. Build/verify on Windows; Puma single-mode.
3. **CI matrix** — GitHub Actions (`ubuntu`/`macos`/`windows`): stage bundled Ruby → `bundle install --standalone` against it → `npm ci` → electron-builder → attach installers to a Release on tag.
4. **Signing & distribution** — provision certs/accounts, wire secrets into CI, choose a distribution channel (GitHub Releases vs. website).
5. **(Optional) auto-update** — electron-updater against GitHub Releases.
