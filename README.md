# Simply Suite

A Sinatra-based invoicing and client management web application. Manage clients, create invoices, generate PDFs, and email invoices to clients.

## Features

- Client management (create, view, edit)
- Invoice creation with line-item services
- PDF invoice generation (via Prawn)
- Invoice lifecycle: draft → approved → sent → paid
- Email delivery of invoices (via ActionMailer)
- Session-based authentication

## Requirements

- Ruby (1.9.x era — compatible with the pinned gem versions)
- MySQL
- Bundler

## Setup

### 1. Install dependencies

```bash
bundle install
```

### 2. Create the logs directory

The app writes logs to `logs/` at startup and will crash if it doesn't exist:

```bash
mkdir -p logs
```

### 3. Configure the database

Edit `config/_app_settings.rb` and set your MySQL credentials and environment:

```ruby
ENV['RACK_ENV'] = "development"   # or "production"
ENV['DATABASE_URL'] = "mysql://username:password@host/dbname"
```

There is no `.env` file — configuration is done directly in this file.

### 4. Set up the database

On first run in development mode, DataMapper will auto-migrate tables. You can also trigger a manual upgrade via the admin route once logged in:

```
GET /upgrade-db
```

### 5. Create a user

There is no public registration flow (it is commented out in `app/auth.rb`). You'll need to insert a user record directly into the database, or temporarily uncomment the registration routes in `app/auth.rb` to create the first admin user.

The `User` model uses `Sinatra::SessionAuth::ModelHelpers` for password hashing — the `hashed_password` and `salt` fields are managed by that gem.

### 6. Add a logo

Invoice PDFs expect a logo image at:

```
public/css/images/logo.png
```

Place your logo there before generating any invoices.

## Running the app

```bash
bundle exec thin -p 9393 -R config.ru start
```

Or via Foreman/Procfile:

```bash
foreman start
```

The app will be available at `http://localhost:9393`.

## Routes

| Path | Description |
|------|-------------|
| `/` | Admin dashboard (requires login) |
| `/login` | Login / logout |
| `/clients` | List, create, and edit clients |
| `/invoices/:client_key` | List invoices for a client |
| `/invoices/create/:client_key` | Create a new invoice |
| `/invoices/view/:id` | View invoice with PDF link |
| `/invoices/approve/:id` | Mark invoice approved |
| `/invoices/send/:id` | Email invoice to client |
| `/invoices/paid/:id` | Mark invoice paid |

## Batch invoice sending

To send all approved, unsent, past-due invoices via cron:

```bash
ruby scripts/send_approve_invoices.rb
```

## Deployment

Deployment uses Capistrano. Fill in the server roles in `config/deploy.rb`, then:

```bash
cap deploy:update
```

## Directory structure

```
app/          # Sinatra app classes (admin, auth, clients, invoices)
config/       # App settings and Capistrano deploy config
models/       # DataMapper models (User, Client, Invoice, Service)
views/        # HAML templates
public/       # Static assets and generated PDFs (public/pdfs/)
scripts/      # Standalone scripts for cron jobs
logs/         # Runtime logs (must be created manually)
```
