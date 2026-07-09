# Simply Suite

A Sinatra-based invoicing and client management app. Manage clients, create
invoices, generate PDFs, and email invoices to clients.

![Invoice view](docs/invoice-screenshot.png)

[Sample invoice PDF](docs/sample-invoice.pdf)

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

- `logo` — path to your logo image (relative to where you run the script, or absolute). Leave blank to omit.
- `from` — your company name and address.
- `bill_to` — client name, contact, and address.
- `invoice` — invoice number, date (`YYYY-MM-DD`), payment terms, and notes.
- `services` — line items, each with `item`, `description`, `qty`, and `unit_cost`.
- `discount_percentage` — set to `0` for no discount.
- `amount_paid` — any deposit already received; set to `0` if nothing has been paid.

### 5. Generate the PDF

    bundle exec ruby scripts/invoice_from_json.rb my-invoice.json

The PDF is saved alongside the JSON file — `my-invoice.pdf` in this example.

---

## Stack

Ruby 3.3 · Sinatra 4 · Sequel ORM · SQLite (default) or MySQL · Puma ·
Tailwind CSS · Hotwire (Turbo + Stimulus)

## Requirements

- Ruby 3.3
- Bundler
- SQLite3 (default) or MySQL
- The Tailwind standalone CLI binary (see Setup)

## Setup

### 1. Install gems

    bundle install

### 2. Configure environment

    cp .env.example .env

Edit `.env` — at minimum set:

    DATABASE_URL=sqlite://./db/development.sqlite3
    SESSION_SECRET=any_long_random_string

To use MySQL instead: `DATABASE_URL=mysql2://user:pass@host/dbname`

Leave SMTP vars blank to disable email sending (the Send button will be
greyed out in the UI).

### 3. Download the Tailwind standalone CLI

    curl -sLO https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-linux-x64
    chmod +x tailwindcss-linux-x64
    mv tailwindcss-linux-x64 tailwindcss

### 4. Run migrations

    bundle exec ruby db/migrate.rb

### 5. Create an admin user

    bundle exec ruby db/seeds.rb

### 6. Build Tailwind CSS

    ./tailwindcss -i public/css/input.css -o public/css/tailwind.css

## Running

    bundle exec foreman start

Or manually:

    bundle exec puma -p 9393 -R config.ru   # web server
    ./tailwindcss -i public/css/input.css -o public/css/tailwind.css --watch  # CSS watcher

App runs at http://localhost:9393

## Routes

| Path | Description |
|------|-------------|
| `/` | Dashboard (requires login) |
| `/login` | Login / logout |
| `/clients` | List, create, edit clients |
| `/invoices/:client_key` | List invoices for a client |
| `/invoices/create/:client_key` | New invoice |
| `/invoices/view/:id` | View invoice + PDF |
| `/invoices/approve/:id` | Approve invoice |
| `/invoices/send/:id` | Email invoice (requires SMTP config) |
| `/invoices/paid/:id` | Mark as paid |

## Scripts

### Batch invoice sending

Sends all approved, unsent, past-due invoices. Intended to be run as a cron job.

    bundle exec ruby scripts/send_approve_invoices.rb

### Generate PDF from a JSON file

Generate an invoice PDF from a JSON file without running the app or touching a database.
The PDF is saved alongside the JSON file with the same basename.

    bundle exec ruby scripts/invoice_from_json.rb path/to/invoice.json

**Getting started:**

    cp docs/invoice-template.json my-invoice.json
    # edit my-invoice.json — fill in your company, client, services, and logo path
    bundle exec ruby scripts/invoice_from_json.rb my-invoice.json
    # → my-invoice.pdf

The `logo` field in the JSON is a path to an image file (relative to where you run
the script, or absolute). Leave it as an empty string to omit the logo.

### Generate sample invoice PDF

Generates `docs/sample-invoice.pdf` using the app's PDF renderer with demo data.

    bundle exec ruby scripts/generate_invoice_pdf.rb

### Generate invoice screenshot

Generates `docs/invoice-screenshot.png` — a full-page screenshot of the invoice view.
Requires Chrome or Chromium to be installed.

    bundle exec ruby scripts/generate_invoice_screenshot.rb

## Database

Schema is managed via migrations in `db/migrations/`. To apply:

    bundle exec ruby db/migrate.rb
