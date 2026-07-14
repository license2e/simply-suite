# Simply Suite

A Sinatra-based invoicing and client management app. Manage one or more
businesses, their clients, invoices, and timesheets, and generate PDFs — all
backed by a plain JSON file store (no database).

![Invoice view](docs/invoice-screenshot.png)

[Sample invoice PDF](docs/invoice-template.pdf)

## Generate a PDF invoice (standalone)

No database, no server, no configuration needed — just Ruby and the gem dependencies.

### 1. Prerequisites

- Ruby 3.3 — install with [mise](https://mise.jdx.dev/) (recommended), rbenv, or rvm:

      curl https://mise.run | sh
      mise install ruby@3.3

- Bundler:

      gem install bundler

### 2. Clone the repo

    git clone <repo-url>
    cd simply-suite

### 3. Install gems

    bundle install

### 4. Copy and edit the invoice template

    cp docs/invoice-template.json my-invoice.json

Open `my-invoice.json` and fill in your details:

- `logo` — path to your logo image, relative to the JSON file (or absolute). Leave blank to omit.
- `from` — your company name, contact, email, and address.
- `bill_to` — client name, contact, email, and address.
- `invoice` — invoice number, date (`YYYY-MM-DD`), payment terms, and notes.
- `services` — line items, each with `item`, `description`, `service_date` (`YYYY-MM-DD`), `qty`, and `unit_cost`.
- `discount_percentage` — set to `0` for no discount.
- `amount_paid` — any deposit already received; set to `0` if nothing has been paid.

### 5. Generate the PDF

    bundle exec ruby scripts/invoice_from_json.rb my-invoice.json

The PDF is saved alongside the JSON file — `my-invoice.pdf` in this example.

---

## Stack

Ruby 3.3 · Sinatra 4 · JSON file store (no database) · Puma ·
Tailwind CSS · Prawn (PDF)

## Requirements

- Ruby 3.3
- Bundler
- The Tailwind standalone CLI binary (see Setup)

## Setup

### 1. Install gems

    bundle install

### 2. Configure environment

    cp .env.example .env

Edit `.env` — at minimum set:

    SESSION_SECRET=any_long_random_string

Optionally set `DATA_DIR` to change where business data is stored (defaults
to `./data`; see [Data](#data) below).

### 3. Download the Tailwind standalone CLI

    curl -sLO https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-linux-x64
    chmod +x tailwindcss-linux-x64
    mv tailwindcss-linux-x64 tailwindcss

### 4. Build Tailwind CSS

The `public/css/input.css` file uses `@source` directives to scan ERB and Ruby
files for class names — Tailwind only emits CSS for classes it finds there.
Always rebuild after pulling changes:

    ./tailwindcss -i public/css/input.css -o public/css/tailwind.css

There's no database to migrate and no seed user to create — the first run
creates or selects a business right in the browser (see Onboarding below).

## Running

### With Claude Code (recommended)

    /dev          # start server + Tailwind watcher in background (auto-reloads)
    /dev stop     # stop everything

### Manually

    bundle exec foreman start   # uses Procfile (puma + Tailwind via rerun)

Or individually:

    bundle exec rerun --no-notify -- bundle exec puma -p 9393     # web server
    bundle exec rerun --no-notify \
      --pattern "views/**/*.erb,app/**/*.rb,public/css/input.css" \
      -- ./tailwindcss -i public/css/input.css -o public/css/tailwind.css   # CSS

App runs at http://localhost:9393

### Onboarding

There's no login and no seed data. The first request redirects to
`/businesses`, where you create your first business (name + address, optional
logo) or, once one exists, pick which business to work in. The chosen
business is kept in the session — everything else (clients, invoices,
timesheets) is scoped underneath it.

## Desktop app

Simply Suite can run as a self-contained desktop app: an Electron window that
supervises the Sinatra/Puma server and renders the UI. The packaged build
bundles its own Ruby runtime, so end users need no Ruby, Bundler, or mise. The
Electron layer lives in `desktop/` and is additive — the web app is unchanged
and still runs with `foreman` as above.

### Run from source (needs Ruby + gems installed)

    cd desktop
    npm install
    npm start          # first run asks where to store data, then opens the app

It spawns the Sinatra app on a random loopback port and loads it in the window.
Use **File → Data folder…** to move your data later (copied with checksum
verification, old copy removed only after the new one is verified).

### Build the offline installer

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

### Running the AppImage

AppImages need FUSE 2. On modern Ubuntu/lubuntu (which ship FUSE 3 only),
either install it once:

    sudo apt install libfuse2         # then run the AppImage directly

or run without installing anything:

    "./dist/Simply Suite-<ver>.AppImage" --appimage-extract-and-run

### Installing an unsigned build

These builds are not code-signed, so the OS shows a warning the first time.

**macOS** — after dragging the app to Applications, clear the download
quarantine flag (the right-click → Open bypass is unreliable on recent macOS):

    xattr -dr com.apple.quarantine "/Applications/Simply Suite.app"

**Windows** — on the SmartScreen prompt, click **More info → Run anyway**.

### Data location

Per-user, outside the app bundle (survives reinstalls/upgrades):

- Linux: `~/.config/Simply Suite/data`
- macOS: `~/Library/Application Support/Simply Suite/data`
- Windows: `%APPDATA%\Simply Suite\data`

…or any writable folder you choose during onboarding or via File → Data folder….

### Releases & CI

A GitHub Actions workflow (`.github/workflows/desktop.yml`) builds Linux, macOS
(arm64 + x86_64), and Windows installers. It is currently **manual-only**
(`workflow_dispatch`) — run it from the repository's Actions tab to build all
platforms and upload the installers as workflow artifacts. To enable automatic
builds, uncomment the `push` (tag `v*`) and `pull_request` triggers in the
workflow: a `v*` tag then publishes the installers to a GitHub Release, and pull
requests that touch the app or `desktop/` files build the matrix and upload
artifacts.

## Routes

| Path | Description |
|------|-------------|
| `/` | Dashboard (requires an active business) |
| `/businesses` | Create a business, or choose one to switch into |
| `/businesses/logo` | Serves the current business's logo |
| `/clients` | List clients |
| `/clients/create` | New client |
| `/clients/view/:client_key` | View client |
| `/clients/edit/:client_key` | Edit client |
| `/clients/delete/:client_key` | Soft-delete client (and its invoices) |
| `/timesheets` | Timesheets overview, all clients |
| `/timesheets/:client_key` | Timesheet for one client/period (`?period=YYYY-MM`) |
| `/timesheets/:client_key/invoice` | Roll un-invoiced entries in a period into a draft invoice |
| `/settings` | Business info and logo upload |
| `/invoices/:client_key` | List invoices for a client |
| `/invoices/:client_key/create` | New invoice |
| `/invoices/:client_key/:num` | View invoice |
| `/invoices/:client_key/:num/edit` | Edit invoice |
| `/invoices/:client_key/:num/preview` | HTML preview (modal) |
| `/invoices/:client_key/:num/pdf` | Rendered invoice PDF |
| `/invoices/:client_key/:num/approve` | Approve invoice |
| `/invoices/:client_key/:num/mark_sent` | Mark invoice as sent |
| `/invoices/:client_key/:num/paid` | Mark invoice as paid |
| `/invoices/:client_key/:num/delete` | Soft-delete invoice |

## Scripts

### Generate PDF from a JSON file

Generate an invoice PDF from a JSON file without running the app or touching a database.
The PDF is saved alongside the JSON file with the same basename.

    bundle exec ruby scripts/invoice_from_json.rb path/to/invoice.json

**Getting started:**

    cp docs/invoice-template.json my-invoice.json
    # edit my-invoice.json — fill in your company, client, services, and logo path
    bundle exec ruby scripts/invoice_from_json.rb my-invoice.json
    # → my-invoice.pdf

The `logo` field in the JSON is a path to an image file, relative to the JSON file
itself (or absolute). Leave it as an empty string to omit the logo.

### Generate sample invoice PDF

Generates `docs/sample-invoice.pdf` using the app's PDF renderer with demo data.

    bundle exec ruby scripts/generate_invoice_pdf.rb

### Generate invoice screenshot

Generates `docs/invoice-screenshot.png` — a full-page screenshot of the invoice view.
Requires Chrome or Chromium to be installed.

    bundle exec ruby scripts/generate_invoice_screenshot.rb

## Data

All app data — businesses, clients, invoices, timesheets, logos, and
rendered invoice PDFs — lives under a single directory tree as plain JSON
files (plus the PDFs themselves). No database required:

    data/<business-slug>/
      config/
        settings.json       # company info + defaults (timesheet period, terms, notes)
        logo.png            # optional, uploaded via /settings or /businesses
      clients/
        <client-slug>/
          client.json
          invoices/
            <num>.json
            <prefix>-<num>.pdf
            archive/         # soft-deleted invoices
          timesheets/
            <YYYY-MM>.json   # one file per period (granularity is per-client)
        archive/
          <client-slug>/     # soft-deleted clients (whole tree moved here)

The root directory defaults to `./data` and is git-ignored (it's real
business data, never committed). Override it with `DATA_DIR` in `.env` to
point at another location — e.g. a mounted volume for backups.

Slugs (business and client) are assigned once at creation and are immutable;
renaming a business or client never moves its directory.

This app previously stored data in a Sequel/SQLite (or MySQL) database. That
data was migrated to the JSON store with a one-time script
(`scripts/export_to_json.rb`, since removed along with the `sequel`,
`sqlite3`, `mysql2`, `mail`, and `bcrypt` gems) — there is no migration path
left to run; new installs start directly on the JSON store via `/businesses`.
