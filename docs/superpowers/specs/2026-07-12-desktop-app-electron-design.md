# Simply Suite Desktop App — Design

**Date:** 2026-07-12
**Status:** Design (approved in brainstorming, pending spec review)
**Topic:** Ship Simply Suite as an offline, cross-platform desktop app that renders the existing web UI inside a native window.

## 1. Goal

Let people who do **not** have Ruby installed run Simply Suite as a normal desktop
application — double-click an installer, get an app in their Start menu / Applications
/ launcher — with **all data stored locally** and **no internet or hosted server
required**. The app is a native window that renders the existing Sinatra web UI.

Targets: **Windows, macOS, and Linux.**

### Success criteria

- A non-technical user installs a single artifact per OS and runs the app with no
  Ruby, no terminal, no configuration.
- The app works fully **offline**; each user's data lives in a writable location and
  persists across restarts and app upgrades.
- Users can **relocate their data folder** to any writable location they choose (e.g. a
  backed-up or synced folder), with a safe, checksum-verified migration.
- Invoices still generate as PDFs (Prawn), businesses/clients/invoices/timesheets
  all function exactly as in the browser.
- Closing the window cleanly stops the background Ruby server (no orphan processes).

### Non-goals (explicitly out of scope for v1)

- Auto-update (electron-builder supports it later; not now).
- Multi-user, accounts, sync, or any hosted/cloud component.
- Replacing the JSON file store with a database.
- Mobile / web-hosted distribution.
- Changing any application feature or route behavior.

## 2. Key facts about the existing app (constraints)

These shaped the design and were verified against the code:

- **Ruby 3.3 / Sinatra 4 (modular)** app, mounted via `config.ru` with `set :run, false`.
  Served by **Puma** (Procfile uses `puma -p 9393`). No dedicated `config/puma.rb`.
- **Data layer is a plain JSON file store** on disk. `Store.data_root` =
  `ENV.fetch('DATA_DIR', APP_ROOT/data)`, and `json_store#write_json` already does
  `FileUtils.mkdir_p` → **pointing `DATA_DIR` at any writable path just works.**
- **Session secret** is `ENV.fetch('SESSION_SECRET', SecureRandom.hex(64))` — a random
  fallback each boot. Sessions only store the currently-selected business (there is
  **no authentication**). We must inject a **persisted** `SESSION_SECRET` so selection
  state survives restarts.
- **PDFs are pure Ruby (Prawn)**: `Prawn::Document.generate`. **Ferrum/headless Chrome
  is a dev/test-only dependency** → the shipped backend needs a Ruby runtime but **no
  bundled Chrome**.
- The app already reads `RACK_ENV`, `DATA_DIR`, `SESSION_SECRET` from the environment,
  so the desktop layer configures everything via env vars — **no route/logic changes.**

## 3. Architecture

Shell: **Electron**. Chosen over Tauri because the hard part is *supervising a bundled
Ruby server and producing signed installers for three OSes* — Electron's ecosystem
(electron-builder: child-process spawn, installers, signing, notarization) is the most
paved road for exactly that, it bundles its own Chromium (identical rendering on every
machine, no reliance on the user's OS webview), and its only real cost — bundle size —
is irrelevant for a desktop invoicing tool. On Linux especially, Electron's
self-contained Chromium avoids depending on a WebKitGTK version the user may not have.

Electron's main (Node) process acts as a **supervisor** around the *unchanged* Ruby
server:

```
┌─ Electron main process (Node) ──────────────────────────────┐
│ 1. pick a free 127.0.0.1 port                               │
│ 2. spawn bundled Ruby → boots Puma on that port             │
│    env: PORT, DATA_DIR, SESSION_SECRET, RACK_ENV=production  │
│ 3. poll until server is ready  (splash window meanwhile)    │
│ 4. BrowserWindow.loadURL(http://127.0.0.1:<port>)           │
│ 5. on quit → gracefully terminate the Ruby child            │
└─────────────────────────────────────────────────────────────┘
        │ spawns
        ▼
┌─ Ruby child process ────────────────────────────────────────┐
│ bundled Ruby 3.3 + vendored gems → Puma → config.ru (Sinatra)│
│ writes JSON data under DATA_DIR (per-user app-data dir)      │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 Launch lifecycle (detail)

1. **Free port**: Electron opens an ephemeral `net` server on `127.0.0.1:0`, reads the
   assigned port, closes it, and passes that port to Ruby via `PORT`. (Never the
   hardcoded 9393 — avoids collisions.) On the rare bind race, retry with a new port.
2. **Spawn**: launch the bundled Ruby launcher (§4.2) with env
   `PORT`, `DATA_DIR`, `SESSION_SECRET`, `RACK_ENV=production`. Bind **loopback only**.
3. **Readiness poll**: repeatedly `GET http://127.0.0.1:<port>/health` (a new trivial
   route, §5) until 200 or timeout (~30 s). Show a lightweight splash window during boot;
   on timeout, show an error window with the captured Ruby log.
4. **Show**: create the main `BrowserWindow`, `loadURL` the local server, hide splash.
5. **Shutdown**: on `window-all-closed` / `before-quit`, send `SIGTERM` to the Ruby
   child, then `SIGKILL` after a grace period. On Windows, kill the process tree
   (`taskkill /pid <pid> /T /F`). Guard against orphans if Electron itself is killed.

### 3.2 Single instance

Use Electron's `app.requestSingleInstanceLock()`. A second launch focuses the existing
window instead of spawning a second server against the same data directory (the JSON
store's atomic tmp-write-then-rename is safe within one process but not across
concurrent writers).

### 3.3 Security posture

- Server binds **`127.0.0.1` only** — never exposed to the network.
- `BrowserWindow` webPreferences: `contextIsolation: true`, `nodeIntegration: false`,
  `sandbox: true`. A minimal `preload.js` (no privileged bridge needed for v1).
- Navigation is confined to the local origin (block/`shell.openExternal` for external
  links).

### 3.4 Data location, settings, and configurability

Simply Suite stores its JSON data in a **dedicated, SS-owned folder** — it only ever
creates or deletes *that* folder, never a parent the user picked (so pointing it at,
say, `~/Documents` can't destroy unrelated files). A small marker file
(`.simply-suite.json`, holding a schema version) identifies a folder as an SS data
folder for detection.

- **Default** (recommended): `<userData>/data`, where `userData` =
  Electron `app.getPath('userData')`:

  | OS | `userData` |
  |----|------------|
  | Windows | `%APPDATA%\Simply Suite` |
  | macOS | `~/Library/Application Support/Simply Suite` |
  | Linux | `~/.local/share/Simply Suite` (XDG) |

- **Custom**: the user picks any writable **parent** folder; SS uses
  `<parent>/Simply Suite/` as the data folder (and says so in the dialog). If the user
  instead points directly at an existing SS data folder (marker present), SS adopts it
  in place rather than nesting.

The resolved data-folder path is persisted — alongside `SESSION_SECRET` — in Electron's
`userData/config.json`, read **before** the Ruby server starts and injected as
`DATA_DIR`. The Ruby app is unchanged: it just honors `DATA_DIR`; the marker and all
directory management live in the Electron main process. Ruby stdout/stderr is piped to
`userData/logs/server.log`.

### 3.5 First-run onboarding (data location)

On first launch (no data path saved yet), before the main window appears, a small
onboarding screen offers:

- **Use the default location** (recommended) → `<userData>/data`.
- **Choose a folder…** → native OS folder picker. SS resolves the target (an existing SS
  folder in place, else `<picked>/Simply Suite`); **if it already contains SS data, that
  data is adopted as-is — never overwritten**; if empty, it is initialized fresh (marker
  written).

The choice is saved to settings and the server boots against it. There is **no
copy/delete migration at onboarding** — a fresh install has nothing to migrate from.

### 3.6 Changing the data directory later (migration)

Triggered from a native application-menu item ("Data folder…"). The whole migration runs
in the Electron main process:

1. **Pick** a new location (native folder picker) → resolve `newDir` as in §3.5.
2. **Write-permission test** — write then delete a temp file in `newDir`; abort with an
   error if it fails.
3. **Conflict check** — if `newDir` already holds SS data (marker present) and isn't the
   current folder: **warn and ask** — *Adopt* the target's data (switch to it; the current
   folder is left untouched — not copied, not deleted) or *Cancel*. Neither side is ever
   auto-destroyed.
4. Otherwise **migrate** into the empty/new target:
   1. **Stop** the Ruby server (release file handles).
   2. **Copy** the current data-folder tree → `newDir`.
   3. **Verify** with **content checksums** — hash + size of every file must match. On any
      mismatch: delete the partial copy, keep the old folder and setting, restart the
      server on the old folder, and show an error.
   4. **Delete** the previous SS data folder (only that dedicated folder).
   5. **Persist** `dataDir = newDir` to settings.
   6. **Restart** the Ruby server against `newDir`.
5. **Adopt path** (from step 3): stop the server → save `dataDir = newDir` → restart on
   `newDir`. No copy; the old folder is left intact.

**Fail-safe invariant:** the previous data folder is deleted **only** after a
byte-verified copy. Any earlier failure leaves the old folder, the saved setting, and the
running app untouched (still on the old data). A progress/splash view is shown during the
move, and the window reconnects when the server restarts.

## 4. Ruby-runtime bundling (embedded Ruby) — the core mechanism

Strategy: **embedded relocatable Ruby + vendored standalone gems**, built per-OS. Chosen
over Tebako because Puma/nio4r native extensions ship as ordinary pre-compiled files
here (fewest cross-OS surprises, and Windows — Tebako's weak spot — is a first-class
target).

### 4.1 Bundle layout (inside Electron `extraResources`)

```
resources/
  app/                      # copy of the Sinatra app: config.ru, app/, lib/,
                            #   views/, public/, plus desktop_boot.rb
  app/vendor/bundle/        # `bundle install --standalone` output
                            #   (gems + natives compiled for THIS os/arch)
  ruby/                     # relocatable Ruby 3.3 runtime for THIS os/arch
    bin/ruby(.exe)
    lib/ruby/...
```

- **Vendored gems**: `bundle install --standalone --path vendor/bundle` (production
  groups only — excludes `development`/`test`, so Ferrum/rspec/foreman are dropped).
  `--standalone` generates `vendor/bundle/bundler/setup.rb`, so **bundler is not needed
  at runtime**; the launcher just requires that file to set load paths.
- **Relocatable Ruby**: build/obtain a Ruby 3.3 that can run from any directory
  (built with `--enable-load-relative`, so it locates its stdlib relative to the
  binary). On Windows, RubyInstaller is already relocatable. Native gems are compiled
  against this exact Ruby in CI on the matching OS/arch.

### 4.2 Boot launcher (`desktop_boot.rb`, new file in the app)

Electron spawns `resources/ruby/bin/ruby resources/app/desktop_boot.rb`. The launcher
avoids any PATH/bin resolution by booting Puma programmatically:

```ruby
# desktop_boot.rb  (runs from resources/app)
ENV['RACK_ENV'] ||= 'production'
require_relative 'vendor/bundle/bundler/setup'   # standalone load paths, no bundler
require 'puma/cli'

port = ENV.fetch('PORT')
Puma::CLI.new([
  '-b', "tcp://127.0.0.1:#{port}",
  '-e', 'production',
  '--dir', __dir__,          # loads ./config.ru
]).run
```

This is the single load-bearing integration point; it is small and OS-agnostic.

### 4.3 Per-OS/arch notes

- **macOS**: build for **arm64 and x64** (Apple Silicon + Intel) — either two artifacts
  or a universal build. Native gems compiled per arch.
- **Windows**: RubyInstaller + MSYS2 devkit available on the `windows-latest` runner via
  `ruby/setup-ruby`; Puma runs in **single mode** (no cluster/fork) — correct for a
  single-user local app anyway.
- **Linux**: build on the oldest reasonable glibc target for portability; ship as
  AppImage (portable) and `.deb`.

## 5. Changes to the existing Ruby app (minimal & additive)

The app is otherwise untouched. Additions:

1. **`desktop_boot.rb`** (new) — the programmatic Puma launcher above.
2. **`/health` route** (new, trivial) — returns `200 "ok"` for the Electron readiness
   poll. Alternatively reuse `GET /`, but a dedicated cheap route is cleaner.
3. **(Optional) `config/puma.rb`** — a minimal production config (single mode, loopback
   bind, sensible thread count). Not strictly required since the launcher passes flags.

Confirmed to need **no** change: `DATA_DIR` handling, `SESSION_SECRET` handling,
`RACK_ENV` switching, PDF generation, routes, views, static assets. The app still runs
bare via `foreman start` for normal development.

The entire configurable-data-folder feature (onboarding, the `config.json` settings
store, the folder marker, and the copy/verify/delete migration of §3.4–3.6) lives
**entirely in the Electron main process** — the Ruby app only ever receives an
already-resolved `DATA_DIR`.

## 6. Repository structure

Add a self-contained desktop layer without disturbing the Ruby app:

```
desktop/
  package.json          # Electron + electron-builder deps, build scripts
  main.js               # supervisor: port, spawn, poll, window, lifecycle
  preload.js            # minimal (contextIsolation)
  splash.html           # boot/splash + error screen
  electron-builder.yml  # targets, signing, extraResources mapping
  build/
    stage-ruby.<os>.*   # produce resources/ruby (relocatable Ruby 3.3)
    vendor-gems.*       # bundle install --standalone (production only)
  assets/               # app icons per OS (.ico/.icns/.png)
```

A build script stages `resources/app` (app source + `desktop_boot.rb`), runs the
gem-vendoring and Ruby-staging steps, then invokes electron-builder.

## 7. Packaging & installers

**electron-builder** targets:

| OS | Format |
|----|--------|
| Windows | NSIS installer (`.exe`) |
| macOS | `.dmg` (arm64 + x64 / universal) |
| Linux | AppImage + `.deb` |

`extraResources` maps `resources/{app,ruby}` into the packaged app. App metadata
(product name "Simply Suite", bundle id, version, icons) set in `electron-builder.yml`.

## 8. Code signing & notarization

- **macOS**: Gatekeeper hard-blocks unsigned apps. Requires an **Apple Developer ID
  ($99/yr)** + **notarization**, configured in electron-builder (`afterSign` notarize
  hook). Without it, users must right-click→Open through a scary warning.
- **Windows**: unsigned `.exe` triggers a SmartScreen "unknown publisher" warning users
  can click through. A code-signing cert (~$100–300/yr, OV/EV) removes it — **optional**
  for v1.
- **Linux**: no signing/gatekeeping. Easiest target.

Signing is wired into the CI build but the certificates/accounts are an operational
prerequisite (see §12 open decisions).

## 9. Continuous integration (build matrix)

Because native gems and the Ruby runtime **cannot be cross-compiled**, each installer is
built on its own OS runner:

- **GitHub Actions** matrix: `windows-latest`, `macos-latest` (arm64 + x64), `ubuntu-latest`.
- Each job, **in order**: (1) **stage the relocatable Ruby 3.3** that will actually ship;
  (2) `bundle install --standalone` (production groups) **using that bundled Ruby**, so
  native extensions are compiled against the exact runtime users get — not a toolchain
  Ruby; (3) `npm ci` in `desktop/`; (4) electron-builder; (5) upload the OS's installer
  as an artifact / attach to a GitHub Release on tag. (`ruby/setup-ruby` may still supply
  a convenience Ruby for tooling, but the *shipped* runtime and its gems must match.)
- macOS job additionally runs notarization (secrets: Apple ID / app-specific password /
  Developer ID cert). Windows job optionally signs (secret: cert).

## 10. Implementation sequence (build order)

The spec covers all of it up front; this is the order of construction, each step
independently testable:

- **Step 0 — Shell on Linux (system Ruby):** Electron `main.js` picks a port, spawns the
  *existing* `puma`, polls `/health`, opens the window, and cleanly kills the child on
  quit. Also builds every Node-side piece that doesn't depend on bundling: the
  `userData/config.json` settings store, persisted `SESSION_SECRET`, first-run onboarding,
  and the full configurable-data-folder migration (§3.4–3.6). Proves the entire UX with
  zero bundling.
- **Step 1 — Embedded Ruby on Linux:** add `desktop_boot.rb`, vendor gems
  (`--standalone`), stage a relocatable Ruby, and swap the spawn to the bundled runtime →
  a genuinely self-contained, offline AppImage/.deb on your own machine. **Retires the
  core bundling risk.**
- **Step 2 — macOS:** stage Ruby (arm64 + x64), build `.dmg`, wire notarization.
- **Step 3 — Windows:** RubyInstaller-based runtime, NSIS installer, optional signing.
- **Step 4 — CI matrix:** GitHub Actions producing all installers on tag.

## 11. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Relocatable Ruby / native-gem loading fragility (the crux) | `--enable-load-relative` Ruby + `--standalone` vendored gems; validate first on Linux (Step 1) before other OSes. |
| Puma/native gem won't load in the bundle | Compile natives in CI on the exact target OS/arch; smoke-test boot in CI. |
| Orphaned Ruby process after crash/force-quit | Track child pid; kill tree on exit; on Windows use `taskkill /T /F`. |
| Port bind race | Retry with a fresh ephemeral port. |
| macOS notarization friction | Standard electron-builder notarize flow; requires Apple Developer account (operational, §12). |
| Data loss on app upgrade | Data lives in `userData`, outside the app bundle — untouched by reinstalls/upgrades. |
| Concurrent writers corrupting JSON | Single-instance lock (§3.2). |
| Migration loses/deletes data | Old folder removed **only** after a byte-verified (checksum) copy; write-perm pre-check; any failure keeps the old folder + setting and restarts on old data; adopt/overwrite conflicts require explicit user choice (§3.6). |
| Destroying a user's shared folder | SS only ever creates/deletes a dedicated named subfolder (+ marker), never the parent the user picked (§3.4). |

## 12. Open decisions (for spec review)

1. **App identity**: product name ("Simply Suite"?), **bundle identifier**
   (e.g. `co.doublenot.simply-suite`?), and icon assets (`.ico`/`.icns`/`.png`).
2. **Code-signing now vs later**: buy Apple Developer ID (mac) and/or a Windows cert
   for v1, or ship unsigned-with-instructions initially and add signing later?
3. **macOS**: universal binary vs separate arm64/x64 artifacts.
4. **Readiness check**: dedicated `/health` route (recommended) vs polling `/`.
5. **Distribution channel**: GitHub Releases, a website download, or hand-delivered
   files?
6. **Data-folder naming**: the dedicated subfolder name (`Simply Suite`?) and marker
   filename (`.simply-suite.json`?).

## 13. Testing / verification strategy

Per OS, a manual smoke test (later automatable):

1. Install from the produced artifact on a clean machine/VM **without Ruby**.
2. Launch → window opens, dashboard loads.
3. Create a business, a client, an invoice; **generate a PDF** (Prawn path).
4. Fully quit and relaunch → data persists; confirm files live under the per-user
   `userData` path.
5. Disable networking → app still works (offline requirement).
6. Quit → confirm **no orphaned Ruby process** remains (Task Manager / `ps`).
7. **Relocate to an empty folder** → data copies, checksum-verifies, the old folder is
   removed, and the app runs against the new one.
8. **Relocate to a folder that already has SS data** → prompted to adopt; adopting
   switches with no copy and leaves the old folder intact.
9. **Simulate a mid-copy failure** → the old data and saved setting are intact and the
   app still runs on the old folder.
10. **Pick a shared folder (e.g. `~/Documents`)** → only a `Simply Suite` subfolder is
    created/removed; sibling files are untouched.
