# Simply Suite — Modernization Design

**Date:** 2026-07-09  
**Status:** Approved  
**Scope:** Full stack modernization — Ruby 3.3, Sequel ORM, SQLite/MySQL, Hotwire + Tailwind, dotenv, mail gem

---

## Overview

Simply Suite is a Sinatra-based invoicing and client management app. The codebase is pinned to 2012-era gems (Sinatra 1.3.2, DataMapper 1.2.0, Ruby 1.9.x) and cannot run on modern Ruby. This spec covers a full modernization in one pass (Option A — big bang), committed incrementally to `main`. The app is not in active use, so no working intermediate state is required.

---

## Section 1: Infrastructure & Configuration

### Branch
Rename `master` → `main`.

### Ruby
Pin to Ruby 3.3 via `.ruby-version`.

### Gemfile

| Removed | Replacement |
|---------|-------------|
| `thin` | `puma` |
| `datamapper`, `ruby-mysql`, `dm-mysql-adapter` | `sequel`, `sqlite3`, `mysql2` |
| `actionmailer` | `mail` |
| `haml` | ERB (stdlib) |
| `multi_json`, `tilt` | removed (bundled in sinatra) |
| `prawn 1.0.0.rc1` | `prawn ~> 2.5` + `prawn-table` |

New additions: `dotenv`, `bcrypt`, `sinatra-contrib`, `rack-flash3`.

**Notes on removed Sinatra extensions:**
- `sinatra/head` — HEAD method support is built into Sinatra 4.x; no replacement needed
- `sinatra/flash` — replaced by `rack-flash3`
- `sinatra/content_for2` — replaced by `sinatra/content_for` from `sinatra-contrib`
- `sinatra/sessionauth` — inlined as `lib/session_auth.rb` (see Section 5)

### Environment Configuration

All secrets and connection details move to `.env` (local dev) / real environment variables (production). `config/_app_settings.rb` becomes a one-liner: `Dotenv.load`.

**`.env.example`** (committed):
```
DATABASE_URL=sqlite://./db/development.sqlite3
SESSION_SECRET=changeme
SMTP_HOST=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
MAIL_FROM=
RACK_ENV=development
```

**`.env`** added to `.gitignore`.

The `DATABASE_URL` scheme (`sqlite://` vs `mysql2://`) is how the database adapter is selected — Sequel handles both automatically with no code changes.

### Server

`Procfile` updated to: `web: bundle exec puma -p 9393`

---

## Section 2: ORM — DataMapper → Sequel

### Schema

Schema moves out of model property declarations and into numbered migration files:

```
db/migrations/001_create_users.rb
db/migrations/002_create_clients.rb
db/migrations/003_create_invoices.rb
db/migrations/004_create_services.rb
db/migrations/005_create_divisions_categories_billing_codes.rb
```

**`db/migrate.rb`** — runs all pending migrations:
```bash
bundle exec ruby db/migrate.rb
```

### DB Connection

`config.ru` establishes the connection:
```ruby
DB = Sequel.connect(ENV['DATABASE_URL'])
```

All models inherit this connection automatically.

### Model Changes

| DataMapper | Sequel |
|------------|--------|
| `property :name, String, required: true` | column in migration + `validates_presence_of :name` |
| `has n, :invoices` | `one_to_many :invoices` |
| `belongs_to :client` | `many_to_one :client` |
| `DataMapper.auto_upgrade!` | `bundle exec ruby db/migrate.rb` |
| `DataMapper.finalize` | removed |

All business logic methods (formatting helpers, `get_status`, `title=`, `editable?`, etc.) move over unchanged.

**Sequel plugins enabled globally:** `validation_helpers`, `timestamps`, `json_serializer`.

### Scripts

`scripts/send_approve_invoices.rb` updated to boot Sequel the same way as `config.ru`.

---

## Section 3: Mailer — ActionMailer → `mail` gem

A single `lib/mailer.rb` replaces scattered `Mailman` class definitions in `app/invoices.rb` and `app/auth.rb`.

```ruby
class Mailer
  def self.invoice(invoice, html_body:, text_body:, pdf_path:)
    build(to: invoice.client.email, subject: "Invoice #{invoice.client.client_prefix}-#{invoice.num}") do |m|
      m.html_part { body html_body }
      m.text_part { body text_body }
      m.add_file pdf_path
    end
  end

  private

  def self.build(to:, subject:, &block)
    mail = Mail.new
    mail.from    = ENV['MAIL_FROM']
    mail.to      = to
    mail.subject = subject
    block.call(mail)
    mail.deliver!
  end
end
```

SMTP configured once in `config.ru` from env vars (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`).

Call sites in `app/invoices.rb`:
```ruby
Mailer.invoice(@invoice, html_body: html_body, text_body: text_body, pdf_path: pdf_path)
```

The forgot-password mailer (already commented out) is left out of scope.

### SMTP Guard

If `SMTP_HOST` is not set, the "Send Invoice" button on the invoice view is rendered as disabled with a tooltip explaining that SMTP is not configured. The `/invoices/send/:id` route also checks for `SMTP_HOST` at runtime and returns a flash error rather than attempting delivery, as a safety net in case the button is bypassed.

---

## Section 4: Frontend — HAML + jQuery → ERB + Tailwind + Hotwire

### Templating

All ~20 HAML view files rewritten as ERB. View file structure maps 1:1:

```
views/
  layouts/
    layout.erb          (was admin/layout.haml)
    layout-login.erb    (was admin/layout-login.haml)
    layout-default.erb  (was admin/layout-default.haml)
  auth/
  clients/
  invoices/
  admin/
  shared/
```

`sinatra-contrib` provides the `content_for` helper used by layouts.

### Tailwind CSS

Delivered via the **Tailwind standalone CLI** (single binary, no Node.js or npm required):

- `tailwind.config.js` — content paths pointing to `views/**/*.erb`
- `public/css/input.css` — Tailwind directives
- Build: `./tailwindcss -i public/css/input.css -o public/css/tailwind.css --watch`

Existing CSS files (`style.css`, `colors.css`, `fonts.css`, `clients.css`, `style.css`) are deleted.

`Procfile` gains a `css` process for the watcher in development:
```
web: bundle exec puma -p 9393
css: ./tailwindcss -i public/css/input.css -o public/css/tailwind.css --watch
```

### Hotwire (Turbo + Stimulus)

Loaded from CDN via `<script type="module">` in the layout — no build step:

```html
<script type="module">
  import * as Turbo from 'https://cdn.jsdelivr.net/npm/@hotwired/turbo@8/dist/turbo.es2017.esm.js'
  import { Application, Controller } from 'https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3/dist/stimulus.js'
  // register controllers inline
</script>
```

`login.js` and `invoices.js` rewritten as small Stimulus controllers (dynamic service line addition/removal on the invoice form, placeholder behavior on login).

jQuery (`jquery-1.7.1.min.js`, `jquery.example.min.js`) removed entirely.

### UI

Clean, minimal business app aesthetic. Neutral sidebar layout matching existing structure: persistent nav sidebar, top header bar, main content area. The `stylesheets <<` / `javascripts <<` pattern in `SimplyBase` is removed — the layout ERB handles asset includes directly.

---

## Section 5: Authentication

`sinatra-sessionauth` (unmaintained, incompatible with Ruby 3.3) is replaced by an inlined `lib/session_auth.rb` module providing identical helpers:

- `authorized?` — checks `session[:auth_user]`
- `authenticate(login, password)` — looks up user, verifies BCrypt password
- `authorize!` — redirects to `/login` if not authorized
- `logout!` — clears session
- `inactivity?` — checks last-activity timestamp

### Password Hashing

Moves to **BCrypt** (`bcrypt` gem). The old gem's hashing scheme is incompatible, so existing user records must be re-created. Since the app is not in active use this is acceptable.

`User` model gains:
- `password=` setter — BCrypt-hashes and stores to `hashed_password`
- `User.authenticate(login, password)` class method

### Session Secret

`ENV['SESSION_SECRET']` replaces the hardcoded string in `base.rb`.

### User Creation

Registration routes remain commented out. A `db/seeds.rb` script is added to create the initial admin user:
```bash
bundle exec ruby db/seeds.rb
```

---

## What's Out of Scope

- Forgot-password email flow (already commented out — left out)
- Deployment config (`config/deploy.rb`, `Capfile`) — left as-is, user can update separately
- PDF layout changes — Prawn logic carries over unchanged, only gem version bumped
- Adding tests — not part of this modernization pass

---

## File Deletions

- `lib/action_mailer.rb`, `lib/prawn.rb`, `lib/thin.rb`, `lib/daemons.rb`
- `public/js/jquery-1.7.1.min.js`, `public/js/jquery.example.min.js`, `public/js/login.js`, `public/js/invoices.js`
- `public/css/style.css`, `public/css/colors.css`, `public/css/fonts.css`, `public/css/clients.css`, `public/css/css-reset.css`
- All `views/**/*.haml` files (replaced by ERB equivalents)
