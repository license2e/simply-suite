# Desktop app: macOS + Windows builds & CI — Design

Date: 2026-07-13
Status: Approved (pending spec review)
Builds on: [2026-07-12-desktop-app-electron-design.md](2026-07-12-desktop-app-electron-design.md)

## Goal

Extend the existing Linux desktop packaging (Electron + embedded Ruby) to also
produce **macOS** and **Windows** installers, and set up **CI** that builds all
platforms and publishes installers to a GitHub Release on a version tag.

The web app and the Electron supervisor logic are already cross-platform in
design. This work fills the three OS-specific gaps — how each OS gets a
relocatable Ruby, how the packaged launcher finds it, and how installers are
built and shipped — plus the automation to do it reproducibly.

## Decisions (from brainstorming)

- **Signing:** ship **unsigned** on all platforms; document the OS workarounds
  (macOS quarantine removal, Windows SmartScreen "Run anyway"). No paid
  developer accounts, no CI secrets. Signing can be added later without rework.
- **CI trigger / distribution:** push a version tag (`v*`) → build every OS →
  attach installers to a **GitHub Release**. Pull requests build + upload
  ephemeral artifacts but do **not** publish. `workflow_dispatch` for manual runs.
- **Verification:** the maintainer has Mac + Windows hardware and will launch the
  installers by hand. CI additionally runs a headless **smoke test** (boot the
  bundled Ruby server, poll `/health`) on each OS before packaging.
- **macOS architectures:** build **both** Apple Silicon (`arm64`) and Intel
  (`x86_64`). A from-source Ruby is single-arch, so this is two separate build
  jobs, not a universal binary.
- **App icon:** out of scope for this round — keep the default Electron icon
  (noted as future polish).

## Non-goals

- Code signing / notarization / stapling.
- Auto-update (electron-updater). `publish: github` is configured only so the
  builder can attach artifacts to a Release; no update feed is consumed.
- ARM Windows, ARM Linux. (x86_64 Linux + Windows; both Mac arches.)
- A custom app icon.

## Architecture

### 1. Unified staged-Ruby directory

Today the Linux Ruby is staged into `desktop/vendor/ruby-linux` and
`electron-builder.yml` maps `vendor/ruby-linux → ruby`. To avoid per-platform
`extraResources` logic, **rename the staging target to `desktop/vendor/ruby`**
(platform-neutral). Each OS's stage script writes the relocatable Ruby into that
same directory; because any given build (CI job or local) stages exactly one OS,
there is never a collision. `electron-builder.yml` keeps a single
`from: vendor/ruby → ruby` mapping unchanged across platforms.

`desktop/vendor` is already git-ignored, so nothing about the rename is committed
except the scripts and the electron-builder mapping.

### 2. Per-OS Ruby stage scripts

Ruby is pinned to **3.3.11** on every OS for parity with the app's dev runtime.

- **`build/stage-ruby-linux.sh`** (existing, renamed target dir): source build,
  `./configure --disable-shared --enable-load-relative --disable-install-doc`.
  Unchanged except `DEST` → `vendor/ruby`.
- **`build/stage-ruby-mac.sh`** (new): same source build as Linux, plus
  `brew install openssl@3 libyaml` and pass
  `--with-openssl-dir="$(brew --prefix openssl@3)"` to `configure`. `--disable-shared`
  statically links libruby; native gems link against libSystem (always present),
  so the result is relocatable within the `.app`. Runs once per arch on the
  matching runner (`macos-14` → arm64, `macos-13` → x86_64); the script itself is
  arch-agnostic and builds for the host arch.
- **`build/stage-ruby-win.ps1`** (new): download the official
  **RubyInstaller-2 "with DevKit"** 7z for 3.3.11 x64, expand it into
  `vendor/ruby`. This layout is already relocatable and ships `bin/ruby.exe`. The
  bundled MSYS2/DevKit is what `stage-gems` uses to compile native gems.

**Interface (shared contract):** after any stage script runs,
`vendor/ruby/bin/ruby` (or `ruby.exe` on Windows) exists and prints
`ruby 3.3.11`, and Bundler is installed into it.

### 3. Cross-OS gem vendoring

`build/vendor-gems.sh` already vendors production gems standalone against
`vendor/ruby`. It works as-is on macOS. For Windows a sibling
**`build/vendor-gems.ps1`** runs the equivalent under the RubyInstaller
environment (via `ridk enable` / the bundled MSYS2 on PATH) so native gems
(puma, nio4r) compile. Both keep the existing `BUNDLE_APP_CONFIG` isolation so
the repo's `.bundle/config` is never clobbered. Output contract is unchanged:
`vendor/bundle/bundler/setup.rb` exists.

Puma runs in **single mode** (no cluster workers), which is supported on Windows;
`desktop_boot.rb` is unchanged.

### 4. Cross-OS launcher fix

The only production source change. `desktop/src/main.js` packaged launcher:

```js
cmd: path.join(
  process.resourcesPath, 'ruby', 'bin',
  process.platform === 'win32' ? 'ruby.exe' : 'ruby'
)
```

`server.js` `stopServer` already branches on `win32` (taskkill vs SIGTERM), so
process teardown needs no change. A unit test asserts the launcher resolves
`ruby.exe` under a simulated `win32` platform and `ruby` otherwise.

### 5. Packaging targets (`electron-builder.yml`)

Keep Linux (`AppImage`, `deb`). Add:

- **`mac`**: target `dmg`; `category: public.app-category.business`;
  `identity: null` and rely on `CSC_IDENTITY_AUTO_DISCOVERY=false` in CI so the
  builder never attempts to sign. Built per-arch; artifact name includes
  `${arch}` so the arm64 and x64 DMGs don't collide on the Release.
- **`win`**: target `nsis`; `oneClick: true`, `perMachine: false` (per-user
  install → no UAC elevation, appropriate for an unsigned app).
- **`publish: github`**: lets a tagged CI run attach artifacts to the Release.
  No update feed is consumed at runtime.

### 6. Smoke test (`build/smoke.js`)

A small Node script (Node is present on every runner) that reuses `src/server.js`:
picks a free port, `startServer` with a launcher pointing at
`vendor/ruby/bin/ruby[.exe]` running `desktop_boot.rb` against a temp
`DATA_DIR`, `waitForHealth`, then `stopServer`. Exit non-zero on failure. This
validates the exact packaged boot path on each OS **before** electron-builder
runs, catching "bundled Ruby can't boot the app" independently of the GUI.
Exposed as `npm run smoke`.

### 7. CI (`.github/workflows/desktop.yml`)

- **Triggers:**
  - `push: tags: ['v*']` → build all, publish to a GitHub Release.
  - `pull_request:` (paths: `desktop/**`, app source, `config.ru`,
    `desktop_boot.rb`, `Gemfile*`) → build all, upload artifacts, no publish.
  - `workflow_dispatch:` → manual, no publish.
- **Matrix:** `ubuntu-latest`, `macos-14` (arm64), `macos-13` (x86_64),
  `windows-latest`.
- **Steps per job:** checkout → setup Node → (Ubuntu only) apt install build
  deps (`libssl-dev libyaml-dev zlib1g-dev`) → restore `vendor/ruby` cache →
  `stage-ruby-<os>` (skipped if cache hit) → `vendor-gems` → `smoke` →
  `electron-builder` (`--publish always` only when the ref is a tag, else
  `--publish never`) → `upload-artifact`.
- **Ruby cache:** `actions/cache` on `desktop/vendor/ruby`, keyed by
  `runner.os + arch + RUBY_VERSION + hash(stage script)`. Saves the ~5–10 min
  recompile on Linux/mac; Windows just re-extracts (fast) but is cached anyway.
- **Permissions/secrets:** `permissions: contents: write`; publish uses the
  built-in `GITHUB_TOKEN`. No signing secrets (unsigned).
- **Reproducible install:** commit `desktop/package-lock.json`; CI uses `npm ci`.

### 8. Documentation (`README.md`)

Under "Desktop app", add:
- **Build on macOS:** `npm run build:ruby:mac` + gems + `npm run dist` →
  `dist/Simply Suite-<ver>-<arch>.dmg`.
- **Build on Windows:** PowerShell `npm run build:ruby:win` + gems + `npm run dist`
  → `dist/Simply Suite Setup <ver>.exe`.
- **Installing unsigned builds:**
  - macOS: after copying to Applications,
    `xattr -dr com.apple.quarantine "/Applications/Simply Suite.app"` (the
    right-click→Open bypass is unreliable on current macOS).
  - Windows: SmartScreen → "More info" → "Run anyway".
- Data locations already documented; unchanged.

`package.json` scripts, made explicit per-OS (no ambiguity): `build:ruby`
(Linux, existing) + new `build:ruby:mac`, `build:ruby:win`; `build:gems`
(Linux/mac, existing) + new `build:gems:win`. The README documents which pair to
run on each OS.

## Testing strategy

- **Unit:** launcher platform-suffix test (win32 → `ruby.exe`, else `ruby`)
  added to the existing `node --test` suite; all existing tests keep passing.
- **Per-OS smoke:** `build/smoke.js` boots the bundled server and asserts
  `/health` on each runner in CI.
- **Manual (maintainer):** download the tagged Release artifacts; launch the DMG
  on both Mac arches and the NSIS installer on Windows; confirm onboarding + a
  business/invoice round-trip.
- **Regression:** the existing Linux AppImage/deb path must still build and smoke
  clean after the `vendor/ruby` rename.

## Risks & mitigations

- **macOS from-source Ruby misses a lib (openssl/yaml/readline):** pin the brew
  deps and pass `--with-openssl-dir`; the smoke test fails loudly in CI if the
  stdlib can't load.
- **Windows native gem compilation:** mitigated by using RubyInstaller
  *with DevKit* and running vendoring under its MSYS2 environment; smoke test
  confirms puma/nio4r loaded.
- **`electron-builder` tries to sign on macOS despite no cert:** `identity: null`
  + `CSC_IDENTITY_AUTO_DISCOVERY=false` disable auto-discovery.
- **`vendor/ruby` rename breaks the working Linux build:** the rename is
  mechanical; the Linux smoke + AppImage build in CI is the guardrail.
- **GitHub Release double-publish across 4 matrix jobs:** electron-builder's
  github publisher is idempotent per-artifact; distinct `${arch}`/OS filenames
  prevent overwrite races.

## Deliverables

1. `build/stage-ruby-linux.sh` (retarget to `vendor/ruby`).
2. `build/stage-ruby-mac.sh` (new).
3. `build/stage-ruby-win.ps1` (new).
4. `build/vendor-gems.sh` (retarget) + `build/vendor-gems.ps1` (new).
5. `build/smoke.js` (new) + `npm run smoke`.
6. `src/main.js` launcher exe-suffix fix + unit test.
7. `electron-builder.yml` mac/win targets + publish config.
8. `.github/workflows/desktop.yml` (new).
9. `desktop/package-lock.json` (committed) + new `package.json` scripts.
10. `README.md` macOS/Windows build + unsigned-install docs.
