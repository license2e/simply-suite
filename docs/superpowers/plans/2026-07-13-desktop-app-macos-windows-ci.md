# Desktop app: macOS + Windows builds & CI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing Linux desktop packaging to also produce macOS (arm64 + x86_64) and Windows installers, and add CI that builds every platform and publishes installers to a GitHub Release on a version tag.

**Architecture:** Each OS stages its own relocatable Ruby 3.3.11 into a single platform-neutral `desktop/vendor/ruby` dir (source build on Linux/mac, RubyInstaller+DevKit on Windows). The Electron packaged launcher gains a `.exe` suffix on Windows — the only production source change. electron-builder adds `dmg`/`nsis` targets alongside the existing AppImage/deb. A per-OS Node smoke test boots the bundled server and polls `/health` before packaging. A GitHub Actions matrix runs the whole pipeline and publishes to a Release on tag.

**Tech Stack:** Node 20 + Electron 33 + electron-builder 25, Ruby 3.3.11 (source build / RubyInstaller-2), Bash + PowerShell stage scripts, GitHub Actions, `node:test`.

## Global Constraints

- **Ruby version:** `3.3.11` on every OS (env `RUBY_VERSION` overridable; default `3.3.11`).
- **Unsigned:** no code signing / notarization. macOS `identity: null` + CI `CSC_IDENTITY_AUTO_DISCOVERY=false`. No signing secrets.
- **Staged-Ruby dir:** always `desktop/vendor/ruby` (git-ignored via existing `desktop/vendor/` rule). Never `vendor/ruby-linux`.
- **Bundler config isolation:** every gem-vendoring script must set `BUNDLE_APP_CONFIG` to a throwaway dir so the repo's `.bundle/config` is never clobbered.
- **Puma runs single-mode** (no cluster workers) — required for Windows. `desktop_boot.rb` is unchanged.
- **Product name:** `Simply Suite` (already set in `package.json` + `electron-builder.yml`).
- **Commit trailer:** every commit ends with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Push after every commit.
- **App root inside the package:** `resources/app`; bundled Ruby at `resources/ruby`. Unchanged.

## File Structure

- `desktop/src/server.js` — add + export `rubyBinName(platform)`.
- `desktop/src/main.js` — packaged launcher uses `rubyBinName()`.
- `desktop/test/rubybin.test.js` — new unit test for `rubyBinName`.
- `desktop/build/stage-ruby-linux.sh` — retarget `DEST` to `vendor/ruby`.
- `desktop/build/vendor-gems.sh` — retarget `RUBY_DIR` to `vendor/ruby`.
- `desktop/build/stage-ruby-mac.sh` — new (macOS source build).
- `desktop/build/stage-ruby-win.ps1` — new (RubyInstaller+DevKit).
- `desktop/build/vendor-gems.ps1` — new (Windows gem vendoring).
- `desktop/build/smoke.js` — new (per-OS boot + `/health` check).
- `desktop/electron-builder.yml` — `vendor/ruby` mapping + mac/win targets + publish.
- `desktop/package.json` — new scripts (`build:ruby:mac`, `build:ruby:win`, `build:gems:win`, `smoke`).
- `desktop/package-lock.json` — new, committed (for `npm ci`).
- `.github/workflows/desktop.yml` — new CI workflow.
- `README.md` — macOS/Windows build + unsigned-install docs.

## Verification note (read before executing)

The Linux dev box can fully verify Tasks 1, 2, 3, 7, 9. Tasks 4, 5, 6 produce macOS/Windows scripts and config that **cannot run on Linux** — their runtime verification is the CI matrix (Task 8) and the maintainer's Mac/Windows hardware. For those tasks, reviewers should check correctness against the documented approach and static linters (shellcheck / YAML parse), **not** attempt to execute them on Linux. Each such task says so explicitly.

---

### Task 1: Cross-OS launcher (`rubyBinName` helper + exe suffix)

**Files:**
- Modify: `desktop/src/server.js` (add `rubyBinName`, export it)
- Modify: `desktop/src/main.js:24-33` (use `rubyBinName()`)
- Test: `desktop/test/rubybin.test.js` (create)

**Interfaces:**
- Produces: `rubyBinName(platform = process.platform) -> 'ruby.exe' | 'ruby'`, exported from `src/server.js`. Consumed by `src/main.js` (Task 1) and `build/smoke.js` (Task 3).

- [ ] **Step 1: Write the failing test**

Create `desktop/test/rubybin.test.js`:

```js
const { test } = require('node:test')
const assert = require('node:assert')
const { rubyBinName } = require('../src/server')

test('rubyBinName returns ruby.exe on win32', () => {
  assert.strictEqual(rubyBinName('win32'), 'ruby.exe')
})

test('rubyBinName returns ruby on macOS and Linux', () => {
  assert.strictEqual(rubyBinName('darwin'), 'ruby')
  assert.strictEqual(rubyBinName('linux'), 'ruby')
})

test('rubyBinName defaults to the current platform', () => {
  const expected = process.platform === 'win32' ? 'ruby.exe' : 'ruby'
  assert.strictEqual(rubyBinName(), expected)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd desktop && node --test test/rubybin.test.js`
Expected: FAIL — `rubyBinName is not a function` (not yet exported).

- [ ] **Step 3: Add `rubyBinName` to `server.js`**

In `desktop/src/server.js`, add this function just above `startServer` (after `augmentedPath`):

```js
// Basename of the Ruby executable for a platform. Windows ships ruby.exe;
// macOS/Linux ship ruby. Used to locate the bundled Ruby in the packaged app.
function rubyBinName(platform = process.platform) {
  return platform === 'win32' ? 'ruby.exe' : 'ruby'
}
```

Then extend the exports line at the bottom of the file:

```js
module.exports = { pickFreePort, rubyLauncher, startServer, waitForHealth, stopServer, rubyBinName }
```

- [ ] **Step 4: Use `rubyBinName()` in `main.js`**

In `desktop/src/main.js`, add `rubyBinName` to the destructured import from `./server` (line 6):

```js
const { pickFreePort, rubyLauncher, startServer, waitForHealth, stopServer, rubyBinName } = require('./server')
```

Then change the packaged `cmd` (line 28) from the hardcoded `'ruby'` to:

```js
      cmd: path.join(process.resourcesPath, 'ruby', 'bin', rubyBinName()),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd desktop && node --test`
Expected: PASS — the new rubybin tests plus all existing tests (server, data-dir, fsutil, migration, settings, stopserver) green.

- [ ] **Step 6: Commit**

```bash
git add desktop/src/server.js desktop/src/main.js desktop/test/rubybin.test.js
git commit -m "feat(desktop): resolve bundled Ruby exe per-platform (ruby.exe on Windows)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 2: Unify the staged-Ruby directory to `vendor/ruby`

**Files:**
- Modify: `desktop/build/stage-ruby-linux.sh:6` (`DEST`)
- Modify: `desktop/build/vendor-gems.sh:6` (`RUBY_DIR`)
- Modify: `desktop/electron-builder.yml:23` (`from:`)

**Interfaces:**
- Produces: staged Ruby at `desktop/vendor/ruby/bin/ruby`. Consumed by `vendor-gems.sh`, `build/smoke.js`, `electron-builder.yml`, and the mac/win scripts (Tasks 4/5).

- [ ] **Step 1: Retarget the Linux stage script**

In `desktop/build/stage-ruby-linux.sh`, change the `DEST` line:

```bash
DEST="$HERE/../vendor/ruby"
```

- [ ] **Step 2: Retarget the gem-vendoring script**

In `desktop/build/vendor-gems.sh`, change the `RUBY_DIR` line:

```bash
RUBY_DIR="$HERE/../vendor/ruby"
```

- [ ] **Step 3: Retarget the electron-builder mapping**

In `desktop/electron-builder.yml`, change the Ruby `extraResources` entry:

```yaml
  # The relocatable Ruby runtime → resources/ruby
  - from: vendor/ruby
    to: ruby
```

- [ ] **Step 4: Verify no stale references remain**

Run: `cd desktop && grep -rn "ruby-linux" . --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=dist`
Expected: no matches (empty output).

- [ ] **Step 5: Stage Ruby into the new dir (Linux dev box)**

Run: `cd desktop && npm run build:ruby`
Expected: compiles Ruby (~5–10 min) and prints `ruby 3.3.11...`. Then confirm:

Run: `cd desktop && ./vendor/ruby/bin/ruby -v`
Expected: `ruby 3.3.11 ...`

- [ ] **Step 6: Commit**

```bash
git add desktop/build/stage-ruby-linux.sh desktop/build/vendor-gems.sh desktop/electron-builder.yml
git commit -m "build(desktop): stage Ruby into platform-neutral vendor/ruby dir

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 3: Per-OS smoke test (`build/smoke.js` + `npm run smoke`)

**Files:**
- Create: `desktop/build/smoke.js`
- Modify: `desktop/package.json` (add `smoke` script)

**Interfaces:**
- Consumes: `rubyBinName`, `pickFreePort`, `startServer`, `waitForHealth`, `stopServer` from `src/server.js`; staged Ruby at `vendor/ruby`; standalone gems at repo-root `vendor/bundle`.
- Produces: `npm run smoke` → exit 0 on `/health` 200, non-zero otherwise.

- [ ] **Step 1: Write the smoke script**

Create `desktop/build/smoke.js`:

```js
// Headless smoke test: boot the *bundled* Ruby server (as the packaged app
// would) and confirm GET /health returns 200. Run on each OS in CI before
// packaging so a broken bundled runtime fails fast, independent of the GUI.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { pickFreePort, startServer, waitForHealth, stopServer, rubyBinName } = require('../src/server')

const DESKTOP_DIR = path.resolve(__dirname, '..')
const APP_DIR = path.resolve(DESKTOP_DIR, '..') // repo root — where desktop_boot.rb lives
const RUBY_BIN = path.join(DESKTOP_DIR, 'vendor', 'ruby', 'bin', rubyBinName())

async function main() {
  if (!fs.existsSync(RUBY_BIN)) {
    console.error(`SMOKE FAIL: bundled Ruby not found at ${RUBY_BIN} — run build:ruby first`)
    process.exit(1)
  }
  // Launch exactly like the packaged app: absolute bundled-Ruby path, no Bundler shim.
  const launcher = (appDir) => ({ cmd: RUBY_BIN, args: [path.join(appDir, 'desktop_boot.rb')] })
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ss-smoke-'))
  const port = await pickFreePort()
  const child = startServer({
    appDir: APP_DIR, dataDir, sessionSecret: 'smoke-secret', port,
    launcher, logStream: process.stdout
  })
  try {
    await waitForHealth(port, { timeoutMs: 60000 })
    console.log('SMOKE OK: /health returned 200')
  } finally {
    await stopServer(child)
    fs.rmSync(dataDir, { recursive: true, force: true })
  }
}

main().catch((err) => {
  console.error('SMOKE FAIL:', err && err.message ? err.message : err)
  process.exit(1)
})
```

- [ ] **Step 2: Add the `smoke` script**

In `desktop/package.json`, add to `"scripts"` (after `"test"`):

```json
    "smoke": "node build/smoke.js",
```

- [ ] **Step 3: Vendor gems, then run the smoke test (Linux dev box)**

The server needs the standalone bundle. Run:

Run: `cd desktop && npm run build:gems`
Expected: ends with `Standalone bundle ready.`

Run: `cd desktop && npm run smoke`
Expected: server boot log, then `SMOKE OK: /health returned 200`, exit code 0.

- [ ] **Step 4: Confirm it fails loudly when Ruby is missing**

Run: `cd desktop && node -e "const p=require('path');const f=p.join(__dirname,'vendor','ruby');require('fs').renameSync(f,f+'.bak')" && (npm run smoke; echo "exit=$?") && node -e "const p=require('path');const f=p.join(__dirname,'vendor','ruby');require('fs').renameSync(f+'.bak',f)"`
Expected: prints `SMOKE FAIL: bundled Ruby not found ...` and `exit=1`, then restores the dir.

- [ ] **Step 5: Commit**

```bash
git add desktop/build/smoke.js desktop/package.json
git commit -m "build(desktop): headless smoke test for the bundled Ruby server

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 4: macOS Ruby stage script (`build/stage-ruby-mac.sh`)

**Files:**
- Create: `desktop/build/stage-ruby-mac.sh`
- Modify: `desktop/package.json` (add `build:ruby:mac`)

**Interfaces:**
- Produces: relocatable Ruby 3.3.11 at `desktop/vendor/ruby` on macOS (host arch). Consumed by `vendor-gems.sh`, `smoke.js`, `electron-builder.yml`.

> **Runtime verification is macOS-only.** Do NOT run this on Linux. Reviewer: check the configure flags, Homebrew deps, and the openssl/psych sanity checks. It runs for real in CI (Task 8, `macos-14` + `macos-13`) and on the maintainer's Mac.

- [ ] **Step 1: Write the macOS stage script**

Create `desktop/build/stage-ruby-mac.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

RUBY_VERSION="${RUBY_VERSION:-3.3.11}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/../vendor/ruby"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# macOS ships neither an OpenSSL nor a libyaml that Ruby's configure finds by
# default (and Homebrew's openssl@3 is keg-only). Install and point at them.
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to build Ruby on macOS." >&2
  exit 1
fi
brew list openssl@3 >/dev/null 2>&1 || brew install openssl@3
brew list libyaml   >/dev/null 2>&1 || brew install libyaml
OPENSSL_DIR="$(brew --prefix openssl@3)"
LIBYAML_DIR="$(brew --prefix libyaml)"
export PKG_CONFIG_PATH="$OPENSSL_DIR/lib/pkgconfig:$LIBYAML_DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

echo "Building relocatable Ruby $RUBY_VERSION ($(uname -m)) -> $DEST"
curl -fsSL "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.gz" -o "$BUILD/ruby.tar.gz"
tar -xzf "$BUILD/ruby.tar.gz" -C "$BUILD"
cd "$BUILD/ruby-${RUBY_VERSION}"

# --disable-shared: static libruby => relocatable inside the .app.
# --enable-load-relative: stdlib located relative to the executable.
./configure --prefix="$DEST" \
  --disable-shared --enable-load-relative --disable-install-doc \
  --with-openssl-dir="$OPENSSL_DIR" \
  --with-libyaml-dir="$LIBYAML_DIR"
make -j"$(sysctl -n hw.ncpu)"
rm -rf "$DEST"
make install

"$DEST/bin/ruby" -v
"$DEST/bin/ruby" -ropenssl -e 'puts "openssl ok: #{OpenSSL::OPENSSL_VERSION}"'
"$DEST/bin/ruby" -rpsych  -e 'puts "psych/libyaml ok: #{Psych::LIBYAML_VERSION}"'
"$DEST/bin/gem" install bundler --no-document
echo "Bundled Ruby (macOS) ready."
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x desktop/build/stage-ruby-mac.sh`

- [ ] **Step 3: Add the `build:ruby:mac` script**

In `desktop/package.json` `"scripts"`, add after `"build:ruby"`:

```json
    "build:ruby:mac": "bash build/stage-ruby-mac.sh",
```

- [ ] **Step 4: Static-lint the script (Linux OK; do not execute)**

Run: `bash -n desktop/build/stage-ruby-mac.sh && echo "syntax ok"`
Expected: `syntax ok`. (If `shellcheck` is installed: `shellcheck desktop/build/stage-ruby-mac.sh` — advisory.)

- [ ] **Step 5: Commit**

```bash
git add desktop/build/stage-ruby-mac.sh desktop/package.json
git commit -m "build(desktop): macOS relocatable Ruby stage script

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 5: Windows Ruby stage + gem scripts (`stage-ruby-win.ps1`, `vendor-gems.ps1`)

**Files:**
- Create: `desktop/build/stage-ruby-win.ps1`
- Create: `desktop/build/vendor-gems.ps1`
- Modify: `desktop/package.json` (add `build:ruby:win`, `build:gems:win`)

**Interfaces:**
- Produces: RubyInstaller Ruby 3.3.11 (x64) at `desktop/vendor/ruby` (`bin/ruby.exe`) and standalone gems at repo-root `vendor/bundle`. Consumed by `smoke.js`, `electron-builder.yml`.

> **Runtime verification is Windows-only.** Do NOT run on Linux. Reviewer: check the RubyInstaller URL/asset name pattern, the silent-install flags, and `BUNDLE_APP_CONFIG` isolation. Exact RubyInstaller release/asset naming (`RUBYINSTALLER_REL`, default `1`) must be confirmed against <https://github.com/oneclick/rubyinstaller2/releases>; it runs for real in CI (Task 8, `windows-latest`) and on the maintainer's Windows box. Native puma/nio4r compilation is confirmed by the smoke test there.

- [ ] **Step 1: Write the Windows stage script**

Create `desktop/build/stage-ruby-win.ps1`:

```powershell
$ErrorActionPreference = 'Stop'

$RubyVersion = if ($env:RUBY_VERSION) { $env:RUBY_VERSION } else { '3.3.11' }
# RubyInstaller package release suffix (the "-1" in RubyInstaller-3.3.11-1).
$Rel = if ($env:RUBYINSTALLER_REL) { $env:RUBYINSTALLER_REL } else { '1' }

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dest = [System.IO.Path]::GetFullPath((Join-Path $Here '..\vendor\ruby'))
$Tmp  = Join-Path $env:TEMP ("ss-ruby-" + [System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

$Asset = "rubyinstaller-devkit-$RubyVersion-$Rel-x64.exe"
$Url   = "https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-$RubyVersion-$Rel/$Asset"
$Exe   = Join-Path $Tmp $Asset

Write-Host "Downloading $Url"
Invoke-WebRequest -Uri $Url -OutFile $Exe

if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
Write-Host "Installing RubyInstaller+DevKit -> $Dest"
# Inno Setup silent switches. /tasks= (empty) => do NOT touch system PATH or
# file associations; this stays a self-contained, relocatable dir tree.
Start-Process -FilePath $Exe -ArgumentList @('/verysilent','/norestart',"/dir=$Dest",'/tasks=') -Wait

# Ensure the MSYS2 MINGW dev toolchain is present so native gems compile.
& "$Dest\bin\ridk.cmd" install 3

& "$Dest\bin\ruby.exe" -v
& "$Dest\bin\gem.cmd" install bundler --no-document
Write-Host "Bundled Ruby (Windows) ready."

Remove-Item -Recurse -Force $Tmp
```

- [ ] **Step 2: Write the Windows gem-vendoring script**

Create `desktop/build/vendor-gems.ps1`:

```powershell
$ErrorActionPreference = 'Stop'

$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root    = [System.IO.Path]::GetFullPath((Join-Path $Here '..\..'))       # repo root
$RubyDir = [System.IO.Path]::GetFullPath((Join-Path $Here '..\vendor\ruby'))

if (-not (Test-Path "$RubyDir\bin\ruby.exe")) {
  Write-Error "Bundled Ruby not found - run build\stage-ruby-win.ps1 first."
}

# Put the bundled Ruby first on PATH for this process. RubyInstaller-2 auto-loads
# its MSYS2 build environment for native gems, so no explicit `ridk enable`.
$env:PATH = "$RubyDir\bin;$env:PATH"

# Isolate bundler config so `bundle config set --local` does NOT clobber the
# repo's own .bundle/config.
$env:BUNDLE_APP_CONFIG = (Join-Path $env:TEMP ("ss-bundle-" + [System.Guid]::NewGuid().ToString()))
New-Item -ItemType Directory -Path $env:BUNDLE_APP_CONFIG | Out-Null

Set-Location $Root
Write-Host "Vendoring production gems with $(& "$RubyDir\bin\ruby.exe" -v)"

& "$RubyDir\bin\bundle.cmd" config set --local path 'vendor/bundle'
& "$RubyDir\bin\bundle.cmd" config set --local without 'development test'
& "$RubyDir\bin\bundle.cmd" install --standalone

if (Test-Path "$Root\vendor\bundle\bundler\setup.rb") { Write-Host "Standalone bundle ready." }
Remove-Item -Recurse -Force $env:BUNDLE_APP_CONFIG
```

- [ ] **Step 3: Add the Windows scripts to package.json**

In `desktop/package.json` `"scripts"`, add:

```json
    "build:ruby:win": "powershell -ExecutionPolicy Bypass -File build/stage-ruby-win.ps1",
    "build:gems:win": "powershell -ExecutionPolicy Bypass -File build/vendor-gems.ps1",
```

- [ ] **Step 4: Static-lint the PowerShell (Linux OK; do not execute)**

If `pwsh` is available:
Run: `pwsh -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path desktop/build/stage-ruby-win.ps1), [ref]$null, [ref]$null); $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path desktop/build/vendor-gems.ps1), [ref]$null, [ref]$null); 'parse ok'"`
Expected: `parse ok`.
If `pwsh` is not installed, skip — the CI `windows-latest` job is the parser/runtime of record.

- [ ] **Step 5: Commit**

```bash
git add desktop/build/stage-ruby-win.ps1 desktop/build/vendor-gems.ps1 desktop/package.json
git commit -m "build(desktop): Windows Ruby (RubyInstaller+DevKit) stage + gem scripts

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 6: electron-builder macOS + Windows targets

**Files:**
- Modify: `desktop/electron-builder.yml`

**Interfaces:**
- Produces: `.dmg` (per arch, name includes `${arch}`) on macOS, `.exe` NSIS installer on Windows, plus the existing AppImage/deb on Linux. `publish: github` enables Release attachment when the builder is invoked with `--publish always`.

> **Runtime verification is mac/Windows-only** (packaging). Reviewer: check YAML validity and the target/identity/publish keys. Real packaging happens in CI (Task 8) and on the maintainer's hardware.

- [ ] **Step 1: Add mac/win targets and publish config**

Edit `desktop/electron-builder.yml` so the full file reads:

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
  - from: vendor/ruby
    to: ruby
linux:
  target:
    - AppImage
    - deb
  category: Office
mac:
  target:
    - dmg
  category: public.app-category.business
  # Unsigned: never attempt to sign or notarize.
  identity: null
dmg:
  # Two Mac build jobs (arm64, x86_64) publish to one Release — keep names distinct.
  artifactName: ${productName}-${version}-${arch}.${ext}
win:
  target:
    - nsis
nsis:
  # Per-user install (no admin/UAC) — appropriate for an unsigned app.
  oneClick: true
  perMachine: false
publish:
  provider: github
```

- [ ] **Step 2: Validate the YAML parses**

Run: `cd desktop && node -e "const yaml=require('js-yaml');const fs=require('fs');yaml.load(fs.readFileSync('electron-builder.yml','utf8'));console.log('yaml ok')"`
Expected: `yaml ok`.
(If `js-yaml` is not resolvable standalone, use: `node -e "require('electron-builder/out/index'); console.log('present')"` is NOT reliable — instead `npx --yes js-yaml electron-builder.yml >/dev/null && echo 'yaml ok'`.)

- [ ] **Step 3: Confirm the Linux build still produces artifacts (Linux dev box)**

Prereq: Tasks 2 + 3 already staged `vendor/ruby` and vendored gems on this box.
Run: `cd desktop && npm run dist -- --publish never`
Expected: electron-builder builds `dist/Simply Suite-<ver>.AppImage` and `dist/simply-suite-desktop_<ver>_amd64.deb` (no publish attempted, no signing). Confirm:

Run: `cd desktop && ls dist/*.AppImage dist/*.deb`
Expected: both files listed.

- [ ] **Step 4: Commit**

```bash
git add desktop/electron-builder.yml
git commit -m "build(desktop): dmg + nsis targets, unsigned, GitHub publish

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 7: Commit `package-lock.json` for reproducible CI

**Files:**
- Create: `desktop/package-lock.json`

**Interfaces:**
- Produces: a lockfile so CI's `npm ci` is deterministic. Consumed by Task 8.

- [ ] **Step 1: Generate the lockfile**

Run: `cd desktop && npm install --package-lock-only`
Expected: creates `desktop/package-lock.json` without modifying `node_modules`.

- [ ] **Step 2: Confirm it is not git-ignored**

Run: `cd desktop && git check-ignore package-lock.json; echo "ignored=$?"`
Expected: `ignored=1` (not ignored — `git check-ignore` exits 1 when the path is NOT ignored).

- [ ] **Step 3: Verify a clean install works from the lockfile**

Run: `cd desktop && rm -rf node_modules && npm ci`
Expected: installs electron + electron-builder from the lockfile with no errors.

- [ ] **Step 4: Sanity-check the test suite still runs post-`npm ci`**

Run: `cd desktop && node --test`
Expected: all tests pass (as in Task 1 Step 5).

- [ ] **Step 5: Commit**

```bash
git add desktop/package-lock.json
git commit -m "build(desktop): commit package-lock.json for npm ci in CI

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 8: CI workflow (`.github/workflows/desktop.yml`)

**Files:**
- Create: `.github/workflows/desktop.yml`

**Interfaces:**
- Consumes: `npm ci`, `build:ruby|build:ruby:mac|build:ruby:win`, `build:gems|build:gems:win`, `smoke`, `dist` scripts; `desktop/vendor/ruby`; `electron-builder.yml` publish config.
- Produces: on PR/dispatch — uploaded artifacts per OS; on tag `v*` — a GitHub Release with all installers attached.

> **Verification is "open a PR / push a tag and watch Actions."** Static YAML validation is the only Linux-local check. This task is where Tasks 4/5/6 first execute for real.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/desktop.yml`:

```yaml
name: desktop

on:
  push:
    tags:
      - 'v*'
  pull_request:
    paths:
      - 'desktop/**'
      - 'app/**'
      - 'views/**'
      - 'public/**'
      - 'config.ru'
      - 'desktop_boot.rb'
      - 'Gemfile'
      - 'Gemfile.lock'
      - '.github/workflows/desktop.yml'
  workflow_dispatch:

permissions:
  contents: write

env:
  RUBY_VERSION: '3.3.11'

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: ubuntu-latest
            ruby_script: build:ruby
            gems_script: build:gems
            stage_file: build/stage-ruby-linux.sh
          - os: macos-14        # Apple Silicon (arm64)
            ruby_script: build:ruby:mac
            gems_script: build:gems
            stage_file: build/stage-ruby-mac.sh
          - os: macos-13        # Intel (x86_64)
            ruby_script: build:ruby:mac
            gems_script: build:gems
            stage_file: build/stage-ruby-mac.sh
          - os: windows-latest  # x64
            ruby_script: build:ruby:win
            gems_script: build:gems:win
            stage_file: build/stage-ruby-win.ps1
    runs-on: ${{ matrix.os }}
    defaults:
      run:
        working-directory: desktop
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Linux build deps
        if: runner.os == 'Linux'
        working-directory: .
        run: sudo apt-get update && sudo apt-get install -y libssl-dev libyaml-dev zlib1g-dev

      - name: Cache bundled Ruby
        id: ruby-cache
        uses: actions/cache@v4
        with:
          path: desktop/vendor/ruby
          key: ruby-${{ runner.os }}-${{ runner.arch }}-${{ env.RUBY_VERSION }}-${{ hashFiles(format('desktop/{0}', matrix.stage_file)) }}

      - name: Install JS deps
        run: npm ci

      - name: Stage Ruby
        if: steps.ruby-cache.outputs.cache-hit != 'true'
        run: npm run ${{ matrix.ruby_script }}

      - name: Vendor gems
        run: npm run ${{ matrix.gems_script }}

      - name: Smoke test
        run: npm run smoke

      - name: Package (no publish)
        if: ${{ !startsWith(github.ref, 'refs/tags/') }}
        run: npm run dist -- --publish never
        env:
          CSC_IDENTITY_AUTO_DISCOVERY: 'false'

      - name: Package and publish to Release
        if: ${{ startsWith(github.ref, 'refs/tags/') }}
        run: npm run dist -- --publish always
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          CSC_IDENTITY_AUTO_DISCOVERY: 'false'

      - name: Upload build artifacts
        if: ${{ !startsWith(github.ref, 'refs/tags/') }}
        uses: actions/upload-artifact@v4
        with:
          name: simply-suite-${{ matrix.os }}-${{ runner.arch }}
          path: |
            desktop/dist/*.AppImage
            desktop/dist/*.deb
            desktop/dist/*.dmg
            desktop/dist/*.exe
          if-no-files-found: ignore
```

- [ ] **Step 2: Validate the workflow YAML parses**

Run: `npx --yes js-yaml .github/workflows/desktop.yml >/dev/null && echo "yaml ok"`
Expected: `yaml ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/desktop.yml
git commit -m "ci: build desktop installers for linux/macOS/windows, publish on tag

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

- [ ] **Step 4: Exercise CI via a PR (verification)**

Open a PR from `feat/desktop-app` to `master` (or push a throwaway branch touching `desktop/`). Watch the `desktop` workflow: all four jobs (ubuntu, macos-14, macos-13, windows) must reach a green `Smoke test` and produce uploaded artifacts. Fix any per-OS failures surfaced here (this is where mac/Windows scripts get their first real run). Do not tag/publish until all four are green.

---

### Task 9: README — macOS/Windows build + unsigned-install docs

**Files:**
- Modify: `README.md` (the "Desktop app" section)

**Interfaces:** none (docs).

- [ ] **Step 1: Extend the build instructions**

In `README.md`, under `### Build the offline installer`, replace the single Linux-centric block so it documents all three OSes. Insert after the existing Linux prerequisites/steps:

```markdown
The build is per-OS — run it on the OS you are packaging for (you cannot
cross-build Ruby). Each OS stages its own relocatable Ruby into
`desktop/vendor/ruby`.

**Linux** (prereqs: `gcc`, `make`, `libssl-dev`, `libyaml-dev`, `zlib1g-dev`):

    cd desktop
    npm install
    npm run build:ruby     # compile relocatable Ruby 3.3 (~5-10 min)
    npm run build:gems
    npm run dist           # → dist/Simply Suite-<ver>.AppImage (+ .deb)

**macOS** (prereqs: Xcode command-line tools + Homebrew):

    cd desktop
    npm install
    npm run build:ruby:mac # compiles Ruby for the host arch (arm64 or x86_64)
    npm run build:gems
    npm run dist           # → dist/Simply Suite-<ver>-<arch>.dmg

**Windows** (PowerShell; downloads RubyInstaller+DevKit automatically):

    cd desktop
    npm install
    npm run build:ruby:win
    npm run build:gems:win
    npm run dist           # → dist/Simply Suite Setup <ver>.exe

Every build is unsigned; see "Installing an unsigned build" below.
```

- [ ] **Step 2: Add the unsigned-install section**

In `README.md`, immediately after the `### Running the AppImage` block, add:

```markdown
### Installing an unsigned build

These builds are not code-signed, so the OS shows a warning the first time.

**macOS** — after dragging the app to Applications, clear the download
quarantine flag (the right-click → Open bypass is unreliable on recent macOS):

    xattr -dr com.apple.quarantine "/Applications/Simply Suite.app"

**Windows** — on the SmartScreen prompt, click **More info → Run anyway**.
```

- [ ] **Step 3: Note the CI/release channel**

In `README.md`, at the end of the "Desktop app" section, add:

```markdown
### Releases & CI

Pushing a `v*` tag triggers the `desktop` GitHub Actions workflow, which builds
Linux, macOS (arm64 + x86_64), and Windows installers and attaches them to a
GitHub Release. Pull requests build the same matrix and upload the installers as
workflow artifacts (no Release) so changes are validated on every platform.
```

- [ ] **Step 4: Verify the docs read correctly**

Run: `grep -n "build:ruby:mac\|build:ruby:win\|com.apple.quarantine\|Run anyway\|desktop.*workflow" README.md`
Expected: matches for each new anchor (mac/win scripts, quarantine command, SmartScreen, CI).

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: macOS/Windows desktop build + unsigned-install + CI notes

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

---

## Self-review

**Spec coverage:**
- Unified `vendor/ruby` dir → Task 2. ✓
- Per-OS stage scripts (linux/mac/win) → Tasks 2/4/5. ✓
- Cross-OS gem vendoring (sh + ps1) → Tasks 2/5. ✓
- Launcher exe-suffix fix + unit test → Task 1. ✓
- electron-builder dmg/nsis + unsigned + publish → Task 6. ✓
- Smoke test → Task 3. ✓
- CI matrix (ubuntu/macos-14/macos-13/windows), tag→Release, PR→artifacts, dispatch, cache, GITHUB_TOKEN → Task 8. ✓
- package-lock + npm ci → Task 7. ✓
- README mac/win build + unsigned install → Task 9. ✓
- macOS both arches → Task 8 matrix (`macos-14` + `macos-13`), arch in dmg name → Task 6. ✓

**Placeholder scan:** none — every script/config/step contains full content. The two documented unknowns (`RUBYINSTALLER_REL` asset naming; RubyInstaller silent-install flags) are called out with a concrete default and the CI/hardware verification path, not left as TODO.

**Type consistency:** `rubyBinName` defined and exported in Task 1; consumed by the same name in `main.js` (Task 1) and `smoke.js` (Task 3). `vendor/ruby` path identical across Tasks 2/3/4/5/6/8. `npm run` script names (`build:ruby`, `build:ruby:mac`, `build:ruby:win`, `build:gems`, `build:gems:win`, `smoke`, `dist`) consistent between package.json edits (Tasks 3/4/5) and the CI matrix (Task 8).
