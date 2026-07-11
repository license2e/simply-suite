# Simply Suite — JSON File Storage Design

**Date:** 2026-07-11
**Status:** Approved
**Scope:** Replace the database entirely with a JSON-file data store; add multi-business support, onboarding, and per-client period-bucketed timesheets; drop authentication and email.

---

## Overview

Simply Suite currently runs on Sinatra + Sequel ORM over SQLite/MySQL. This spec converts it into an app that runs entirely on JSON files — no database. On startup the app reads a gitignored `data/` directory that can hold multiple **businesses**; each business has its own config (settings + assets) and its own clients, invoices, and timesheets, all stored as JSON. Generated invoice PDFs are co-located with their invoice JSON. Soft-deletes move records into `archive/` subdirectories.

Four foundational decisions shape this design (all approved):

1. **Data layer:** Sequel is removed and replaced with plain Ruby model objects (POROs) backed by a small JSON store/repository layer, keeping an API close to the current one so routes and views change minimally.
2. **Authentication:** Removed entirely. The app is a trusted, local, single-operator tool. Sessions remain, but only to hold the active-business selection and flash messages.
3. **Existing data:** A one-time export script migrates the current SQLite DB into the new JSON tree; the DB and all migration code are then removed.
4. **Business context:** The active business is chosen via an in-app switcher and held in the session.

---

## Section 1: Data Directory Layout

The data root is `data/` at the repo root, overridable via the `DATA_DIR` env var. It is `.gitignored`. All business/client directory names are **slugs** (lowercase, hyphenated), generated with the existing slug algorithm (`downcase`, strip non-word chars, collapse whitespace/underscores to `-`), de-duplicated with a `-<rand>` suffix on collision.

**Slugs are immutable.** A business or client slug is assigned once at creation and never regenerated. Renaming a business or client updates its `name` field only; it never moves directories (this matches the current app, whose edit path updates `name` directly and never re-invokes `#title=`). This keeps stored file paths, `session[:business]`, and PDF/`invoice_num` references stable.

```
data/                                       # gitignored; override with DATA_DIR
  acme-consulting/                          # business slug
    config/
      settings.json                         # company info + defaults + advanced settings
      logo.png                              # optional; other assets may live here too
    clients/
      archive/                              # soft-deleted clients (whole folder moved here)
      widgets-inc/                          # client slug
        client.json                         # name, prefix, address, period override
        invoices/
          archive/                          # soft-deleted invoices (json + pdf)
          001.json                          # one invoice per file (line items embedded)
          WID-001.pdf                       # generated PDF, co-located
        timesheets/
          archive/                          # soft-deleted entries, mirrored by period file
            2026-07.json
          2026-07.json                      # period bucket (monthly default)
```

**Startup behavior:**
- If `data/` does not exist, create it.
- If `data/` contains no businesses, the app routes the user to onboarding (create a business).
- If it contains businesses, the app shows the business list (select one, or create a new one).

---

## Section 2: JSON Schemas

Timestamps are ISO-8601 strings. Dates are `YYYY-MM-DD`. Money and quantities are JSON numbers.

### `config/settings.json` — the business (replaces the `Company` singleton)

```json
{
  "name": "Acme Consulting, LLC",
  "slug": "acme-consulting",
  "contact": "Your Name",
  "email": "billing@acme.com",
  "street": "123 Main St, Suite 100",
  "city": "Charlotte",
  "state": "NC",
  "zip": "28203",
  "defaults": {
    "timesheet_period": "monthly",
    "terms": "Payable upon receipt",
    "notes": "Thank you for your business"
  },
  "created_at": "2026-07-11T12:00:00Z",
  "updated_at": "2026-07-11T12:00:00Z"
}
```

`defaults.timesheet_period` is one of `daily | weekly | monthly | quarterly` and is the business-wide default (advanced setting; defaults to `monthly`).

### `client.json`

```json
{
  "slug": "widgets-inc",
  "prefix": "WID",
  "name": "Widgets Inc",
  "contact": "Jane Smith",
  "email": "jane@widgets.com",
  "street": "456 Client Ave",
  "street2": "",
  "city": "Charlotte",
  "state": "NC",
  "zip": "28203",
  "timesheet_period": null,
  "created_at": "2026-07-11T12:00:00Z",
  "updated_at": "2026-07-11T12:00:00Z"
}
```

`timesheet_period: null` means inherit the business default; a string value (`daily`/`weekly`/`monthly`/`quarterly`) overrides it for this client.

### invoice `NNN.json` — services embedded as an array (no separate Service records)

```json
{
  "num": "001",
  "invoice_date": "2026-07-09",
  "total_amount": 4750.0,
  "total_discount": 0.0,
  "amount_paid": 0.0,
  "is_complete": true,
  "terms": "Net 30 days",
  "notes": "Thank you for your business.",
  "approved_on": null,
  "sent_at": null,
  "paid_at": null,
  "services": [
    { "item": "Strategy", "desc": "Brand audit", "service_date": "2026-07-01", "qty": 1, "cost": 1500.0 }
  ],
  "created_at": "2026-07-11T12:00:00Z",
  "updated_at": "2026-07-11T12:00:00Z"
}
```

- **`num` is always assigned before the first write.** The current app could persist a draft invoice with a nil/empty `num`; that is no longer allowed, because the filename is keyed on it. On create, `num` is resolved to `next_num` (see Section 3) before the file is written. The filename is `<num>.json` (e.g. `001.json`); the number is per-client.
- **Totals are manual, not derived.** `total_amount`, `total_discount`, and `amount_paid` are whatever the user entered on the form (exactly as today — the app never auto-sums line items into the invoice total). The embedded `services` are line items whose per-line totals are display-only. The one exception is the timesheet roll-up, which *pre-fills* `total_amount` (Section 5); the user can still edit it afterward.
- The PDF is `<prefix>-<num>.pdf` (e.g. `WID-001.pdf`) co-located in the same `invoices/` folder.

### timesheet period file `YYYY-MM.json` (etc.)

```json
{
  "period": "2026-07",
  "granularity": "monthly",
  "entries": [
    {
      "id": "a1b2c3",
      "item": "Development",
      "desc": "Frontend work",
      "service_date": "2026-07-05",
      "qty": 2.0,
      "cost": 125.0,
      "invoiced": false,
      "invoice_num": null,
      "created_at": "2026-07-11T12:00:00Z",
      "updated_at": "2026-07-11T12:00:00Z"
    }
  ]
}
```

Each entry has a generated short `id` (`SecureRandom.hex(3)`), unique within the client's timesheets. `invoiced`/`invoice_num` link an entry to the invoice it was rolled into (`invoice_num` is the target invoice's `num`).

---

## Section 3: Model / Repository Layer (replaces Sequel)

A small `lib/store/` layer of plain Ruby objects. The goal is an API close enough to the current Sequel usage that routes and views change minimally. It keeps the existing `Formattable` mixin, every `formatted_*` helper, `get_status`, `deletable?`/`editable?`, and `city_state_zip`.

### `JsonStore` (low-level)
- Atomic writes: write to a temp file, then `File.rename` into place.
- `read(path)` / `write(path, hash)` / `list(dir)` / `exist?`.
- Slug generation + collision de-duplication.
- All paths are resolved relative to the **active business** directory (except the business list itself, which is resolved from the data root).

### `Business`
- `Business.all` — list businesses from the data root (each dir with a `config/settings.json`).
- `Business.find(slug)` / `Business.create(attrs, logo_upload = nil)` (onboarding — writes `config/settings.json` and, if a logo was uploaded, `config/logo.png`).
- Instance: config accessors (`name`, `contact`, `email`, address, `defaults`), `#update(attrs)` (writes `config/settings.json`; **never** changes the slug/dir), `#save_logo(upload)` (writes `config/logo.png`), `resolve_logo` (returns `{ local:, web: }` where `web` is the logo route from Section 6, or nil), `city_state_zip`.

### `Client`
- `Client.all` (ordered by name), `Client.find(slug)`, `Client.create(attrs)`, `#update` (updates `name` and fields; never changes the slug/dir).
- `#title=` sets name + generates/dedupes slug (ported from current `Client#title=`), used **only** on create.
- `#soft_delete` moves the whole client folder to `clients/archive/<slug>/`.
- `#timesheet_period` resolves the client override or the business default.
- `#timesheet_summary` — scans all `timesheets/*.json` period files and returns `{ total_entries:, uninvoiced_entries: }` for the timesheets index (which today does `Timesheet.where(client_id:).all` and counts). Returns zeros when the client has no period files.

### `Invoice`
- Scoped to a client. `Client#invoices` lists them **ordered by `num.to_i` descending** (never lexical — real numbers span `001`..`10001`, so `"9" > "10"` lexically is wrong). Supports in-memory pagination (slice after listing) so the existing list view's `@page`/`@total_pages`/`@pagination_path` still work.
- `Invoice.find(client, num)`.
- `Invoice.create(client, attrs)` / `#update` — assigns `next_num` on create before writing; persists `<num>.json`. Totals are taken as entered (see Section 2) — no auto-sum.
- `#next_num` — computes the next number as `(max of existing nums by .to_i) + 1`, zero-padded to the width of the client's existing numbers (default 3, e.g. `001`), so `ACM` (starts at `007`) and `LDPNL` (`10001`+) both increment correctly.
- **Services merge strategy:** on each save the whole `services` array is replaced by the submitted rows (empty rows dropped). This removes the id-based add/update/delete machinery (`service_id`, `delete_services`, `Service.first(id:)`); see the form/JS rewrite in Section 4.
- `#soft_delete` moves `<num>.json` and `<prefix>-<num>.pdf` into `invoices/archive/`, **and reconciles timesheets**: any timesheet entry across the client's period files with `invoice_num == this.num` is reset to `invoiced: false, invoice_num: null` so its time can be re-billed (without this, a deleted draft would permanently strand its source entries in the read-only "already invoiced" state).
- Keeps `Formattable`, all `formatted_*`, `get_status`, `deletable?`, `editable?`.
- Services are embedded plain hashes / lightweight value objects exposing `item`, `desc`, `service_date`, `qty`, `cost`, and their `formatted_*` helpers.

### `TimesheetPeriod`
- Resolves a client's granularity, computes the period key for a given date, and the filename.
- `TimesheetPeriod.for(client, period_key)` loads (or builds empty) a bucket; `#save` writes it.
- `#entries`, `#add`/`#update`/`#remove` (remove appends the entry to `archive/<period>.json`).
- Period navigation: `#prev` / `#next` / `#current`.
- Re-bucketing: when an entry's `service_date` moves it to another period, it is removed from the old file and added to the new one on save.
- `#create_invoice` — rolls this period's **un-invoiced** entries into a new **draft** invoice: assigns `next_num`, maps each entry to a service by copying **`item`, `desc`, `service_date`, `qty`, `cost`** only (not `id`, `invoiced`, `invoice_num`, or timestamps), pre-fills `total_amount` as `sum(qty*cost)`, and marks each source entry `invoiced: true` + `invoice_num: <num>`. **No-op returning nil when the period has zero un-invoiced entries.**

### Period key / filename conventions
| Granularity | Key format | Example |
|-------------|-----------|---------|
| daily | `YYYY-MM-DD` | `2026-07-05` |
| weekly | `YYYY-Www` (ISO week) | `2026-W28` |
| monthly | `YYYY-MM` | `2026-07` |
| quarterly | `YYYY-Qn` | `2026-Q3` |

> The four configurable granularities are an **explicit user requirement** (advanced setting, default monthly), not incidental complexity — keep the full set even though the default path is monthly.

---

## Section 4: App Flow, Routing & Business Switcher

### Landing & active-business resolution
- A new `Businesses` controller handles `GET /businesses` (list existing, or onboarding form when none) and `POST /businesses` (create + `config/logo.png` upload). Selecting a business sets `session[:business]` and redirects to the dashboard. It replaces the current `Admin` controller as the `/` app.
- The active-business guard must **not** live in a shared `SimplyBase before` block: `before` filters on `SimplyBase` run in every mounted modular app, so a guard that redirects to `/businesses` would make the onboarding/list routes redirect to themselves (infinite loop) — the same propagation mechanism as today's `before { authorize! }`. Instead, put the guard in a helper (`require_business!`) called from a `before` filter in **only** the app subclasses that need an active business (`Clients`, `Invoices`, `Settings`, `Timesheets`, and the dashboard), leaving the `Businesses` controller exempt.
- A business switcher lives in the nav/layout (shows the current business, links to `/businesses`). This **replaces the "Sign out" link** currently in `views/admin/layout-default.erb`.

### Authentication removed — precise edits (see also Section 9)
- Delete: `app/auth.rb`, `lib/session_auth.rb`, `models/user.rb`, `views/auth/*`, `views/admin/layout-login.erb`, `db/migrations/001_create_users.rb`.
- Edit `app/base.rb` (it is coupled to auth in five places and **must** be updated or every request raises `NameError`): remove `require 'session_auth'`, `helpers SessionAuth::Helpers`, the `session[:last_active_at] = … if authorized?` line in the global `before`, `login_url_redirect`, and `access_role?`.
- Edit `app/admin.rb`: the dashboard authorizes with an **inline** `authorize!` (not a `before` filter); this controller is superseded by `Businesses`/the dashboard, so the inline call is removed with it.
- Remove `before { authorize! }` from `app/clients.rb`, `app/invoices.rb`, `app/settings.rb`, `app/timesheets.rb`, replacing with `require_business!` where appropriate.
- Edit `config.ru`: drop the `map '/login' { run Auth }` mount and the `require_relative 'models/user'`; add the `Businesses` mount.

### Database & email removed — precise edits (see also Section 9)
- Edit `config.ru`: remove the Sequel connect (`DB = Sequel.connect(DATABASE_URL)`) and the `Mail.defaults`/SMTP block; require the new store/models instead of `models/models`.
- **Email (dropped entirely):** delete `lib/mailer.rb`, `lib/action_mailer/*`, `lib/app/mailman.rb`, `scripts/send_approve_invoices.rb`, `views/invoices/html_email.erb`, `views/invoices/text_email.erb`; remove the `/send` route and `smtp_configured?`. The status flow keeps a manual **"Mark as sent"** action (`sent_at`), so `sent`/`late` statuses still work. (Note: nothing in the repo actually schedules the send script — it is a standalone script the README merely *suggests* running via cron; no scheduler/cron config exists to remove.)
- **Unused models:** `Division`, `Category`, `BillingCode` and `db/migrations/005_*` (no routes, views, or references).
- **Static exposure:** remove `/pdfs` and `/client-assets` from the `Rack::Static` `urls` list in `app/base.rb` (otherwise Section 6's claim that PDFs leave the public web root is false). PDFs and the logo are now served by app routes.
- **Gems dropped:** `sequel`, `sqlite3`, `mysql2`, `mail`, `bcrypt`. Kept: `sinatra`, `puma`, `prawn`/`prawn-table`, `dotenv`, `sinatra-contrib`, flash.

### Client routes (integer IDs are gone)
The current client **update** route is `post '/update/:id'` keyed on the integer id (`app/clients.rb:32`, form posts to `/update/#{@client.id}`). It is reslugged to `POST /clients/:client_key`. The edit form's `@action_url` updates accordingly.

### New invoice URLs
`:client_key` denotes the **client slug** value throughout.

| Old | New |
|-----|-----|
| `/invoices/:client_key` | `/invoices/:client_key` (list, paginated) |
| `/invoices/create/:client_key` | `/invoices/:client_key/create` |
| `/invoices/edit/:id` | `/invoices/:client_key/:num/edit` |
| `/invoices/:client_key/:invoice_number` | `/invoices/:client_key/:num` (view) |
| `/invoices/:client_key/:invoice_number/preview` | `/invoices/:client_key/:num/preview` |
| `/invoices/approve/:id` etc. | `/invoices/:client_key/:num/approve` (and `mark_sent`, `paid`, `delete`) |
| — (new) | `/invoices/:client_key/:num/pdf` (streams the co-located PDF; 404 if absent) |

Action links stay GET-based for view parity (acceptable: local, single-user, no auth). Wildcard `:num` routes are registered after the specific action routes (as the current app already does).

### Invoice form / services rewrite
Embedding id-less services breaks the current id-keyed form path, so these change together:
- `views/invoices/_form.erb` and `views/invoices/_service_row.erb`: drop the hidden `invoice[services][i][service_id]` field.
- `views/admin/layout-default.erb`: the Stimulus `removeService` handler stops tracking `invoice[delete_services][]` and simply removes the DOM row.
- `app/invoices.rb` `process_invoice_services`: replaced by a simple map of submitted rows → `services` array (drop `Service.first(id:)`/`Service.create`/`delete_services`).

---

## Section 5: Timesheets + Period Bucketing

- Entries are stored in per-period files, bucketed by each entry's `service_date` using the client's resolved granularity (client override → business default → `monthly`).
- The timesheets **index** (`views/timesheets/index.erb`) lists clients with total/uninvoiced counts; it is rewritten to use `client.slug` and `Client#timesheet_summary` instead of the removed `Timesheet.where(client_id:).all` (client integer ids no longer exist).
- The timesheets **show** page shows **one period at a time** with prev/next navigation (via a `?period=` param), replacing the current "all entries on one page" view. Its bulk-save handler writes into the current period file; entry ids are the generated string ids; re-bucketing moves an entry whose date changed; removed entries go to `archive/<period>.json`. Already-invoiced entries are shown read-only (mirrors today's `entry.invoiced` guard).
- A **"Create invoice from this period"** button generates a **draft invoice** from that period's un-invoiced entries (`TimesheetPeriod#create_invoice`, Section 3). The button is **hidden/disabled when the current period has no un-invoiced entries**, and the underlying method is a no-op returning nil in that case (so navigating to an already-billed period can't create an empty draft).
- Reconciliation on the other side is handled by `Invoice#soft_delete` (Section 3), which un-invoices a deleted draft's source entries.

---

## Section 6: PDF & Logo Handling

### PDFs
- Generated with Prawn (renderer unchanged) into the invoice's `invoices/` folder in the data dir, named `<prefix>-<num>.pdf`.
- **Lifecycle:** a PDF is (re)generated whenever an invoice is created or updated via the form (as today). Draft invoices produced by the timesheet roll-up have **no PDF** until they are first opened/edited and saved. This is expected.
- Served through `GET /invoices/:client_key/:num/pdf`, which streams the file from the data dir and returns **404 (not a stack trace)** when the file is absent. The invoice view's PDF button is suppressed for invoices with no PDF (the view already guards on file existence via `@pdf_invoice_path`).
- This removes PDFs from the public web root (they are no longer world-readable via `public/pdfs/`), which is only actually true once `/pdfs` is dropped from `Rack::Static` (Section 4).

### Logo
- The logo moves to the active business's `config/logo.png`. Because that is outside `public/`, the browser-facing `<img src="<%= @logo_url %>">` in `views/invoices/preview.erb` and `views/settings/index.erb` needs an HTTP route: add `GET /businesses/logo` (active business) that streams `config/logo.png` (404 if absent). `resolve_logo` returns this route as its `:web` value and the on-disk path as `:local` (for Prawn).
- `Settings` `POST /logo` is repointed from the current `LOGO_UPLOAD_PATH = 'client-assets/logo.png'` to writing `config/logo.png` inside the active business directory (via `Business#save_logo`).

---

## Section 7: Migration / Export Script

`scripts/export_to_json.rb`, run once against the existing SQLite DB:

1. Connect to the current DB via Sequel one final time (using the current models, temporarily).
2. Map the single `Company` row → one business directory (`config/settings.json` + copy the existing logo — `public/client-assets/logo.png` or `public/css/images/logo.png` — into `config/logo.png` if present).
3. Export each `Client` → `clients/<slug>/client.json`.
4. Export each `Invoice` (+ its `Service` rows) → `clients/<slug>/invoices/<num>.json` with embedded services; copy the existing `public/pdfs/<client_key>/<prefix>-<num>.pdf` into the co-located `invoices/` folder. **Warn and skip the copy (not the invoice) when a source PDF is missing.**
5. Export `Timesheet` rows → monthly period buckets under each client's `timesheets/`. The current `Timesheet` links to an invoice via the **`invoice_id` foreign key** (there is no `invoice_num` column); resolve `invoice_id` → the target invoice's `num` to populate `invoice_num`, and set `invoiced` accordingly.
6. Report a summary. After a successful run and verification, the DB and all Sequel/migration code are removed.

Soft-deleted rows (`deleted_at` set) are exported directly into the corresponding `archive/` folders.

**Post-migration cleanup (documented step, after verification):** remove the old `public/pdfs/<client_key>/` trees and `public/client-assets/logo.png`, so the privacy outcome in Section 6 is real rather than aspirational.

---

## Section 8: Testing & Sample Scripts

- Specs run against a temp `DATA_DIR` fixture (created/torn down per example).
- **Store/model specs:** slug generation + collision, `JsonStore` atomic read/write, `Business`/`Client`/`Invoice` CRUD + soft-delete/archive, `Invoice#next_num` (mixed-width numbering), `Client#timesheet_summary`, `TimesheetPeriod` bucketing + re-bucketing + `create_invoice` (incl. empty-period no-op), `Invoice#soft_delete` timesheet reconciliation, all `formatted_*` + `get_status`.
- **Request specs:** business onboarding + switcher (+ the `require_business!` redirect and the `/businesses` exemption), client CRUD, invoice CRUD + approve/mark_sent/paid/delete + PDF route (present + 404), logo route, timesheet period navigation + roll-into-invoice.
- Drop `spec/requests/auth_spec.rb`.
- **Sample-data scripts** (`scripts/generate_invoice_pdf.rb`, `scripts/generate_invoice_screenshot.rb`) are more coupled than "swap the DB": they build data via the DB **and** create a `User`, drive the `/login` flow, `require 'session_auth'`/`'mailer'`, navigate a stale `/invoices/view/:id` route, and (in `generate_invoice_pdf.rb`) call `create_invoice_pdf` with a stale 4-arg signature. Rewrite them to build in-memory model objects (or a temp business), drop all auth/login/mailer requires, and use the current 3-arg `create_invoice_pdf` and the new invoice URL.

---

## Section 9: Precise Removal & Edit Checklist

Consolidated so nothing is missed (details above):

**Delete:** `app/auth.rb`, `lib/session_auth.rb`, `models/user.rb`, `models/models.rb` (replaced), `lib/mailer.rb`, `lib/action_mailer/*`, `lib/app/mailman.rb`, `scripts/send_approve_invoices.rb`, `db/migrations/*`, `db/migrate.rb`, `db/seeds.rb`, `db/load_json.rb`, `views/auth/*`, `views/admin/layout-login.erb`, `views/invoices/html_email.erb`, `views/invoices/text_email.erb`, `spec/requests/auth_spec.rb`.

**Edit:** `config.ru` (drop `/login` mount, DB connect, SMTP block, `models/user` require; add store/models + `Businesses` mount), `app/base.rb` (remove all 5 auth couplings; drop `/pdfs` + `/client-assets` from `Rack::Static`), `app/admin.rb` → folded into `Businesses`/dashboard, `app/clients.rb` (reslug update route, drop `authorize!`), `app/invoices.rb` (new URLs, embedded services, PDF route, drop `authorize!`/`/send`), `app/settings.rb` (write to active business config incl. `defaults.timesheet_period`; repoint logo), `app/timesheets.rb` (period navigation + roll-up), the invoice form/service/layout views (services rewrite; switcher replaces Sign out), `README.md` (remove DB/migration/email/cron sections; document `data/`, `DATA_DIR`, onboarding), `Gemfile`/`Gemfile.lock` (drop gems), `.gitignore` (add `data/`; the `public/pdfs`/`public/client-assets` ignores become vestigial), `.env.example` (drop `DATABASE_URL`/SMTP; note `DATA_DIR`).

---

## Minor Defaults (assumed, easily changed)

- Data dir name `data/`, env override `DATA_DIR`.
- Invoice file `<num>.json`, PDF `<prefix>-<num>.pdf`.
- Timesheet entry ids via `SecureRandom.hex(3)`.
- GET-based action links kept for view parity (local, no auth).
- Atomic file writes (temp file + `rename`).
- Client soft-delete moves the whole folder into `clients/archive/`.
- Invoice-number zero-pad width inferred from the client's existing numbers (default 3).

---

## Out of Scope

- Multi-user auth / permissions (explicitly removed).
- Email sending and the batch-send script (explicitly removed).
- Concurrent-writer locking beyond atomic single-file writes (single-operator assumption).
- MySQL / any SQL backend.
- The unused billing-code / division / category taxonomy.
- Renaming a business/client's slug/directory after creation (slugs are immutable).
