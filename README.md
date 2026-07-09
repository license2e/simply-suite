# Simply Suite

A Sinatra-based invoicing and client management app. Manage clients, create
invoices, generate PDFs, and email invoices to clients.

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

### 6. Create an admin user

    bundle exec ruby db/seeds.rb

### 7. Build Tailwind CSS

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

## Batch invoice sending (cron)

    ruby scripts/send_approve_invoices.rb

Sends all approved, unsent, past-due invoices.

## Database

Schema is managed via migrations in `db/migrations/`. To apply:

    bundle exec ruby db/migrate.rb
