# Simply Suite Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize Simply Suite from Ruby 1.9/DataMapper/HAML/jQuery to Ruby 3.3/Sequel/ERB+Tailwind+Hotwire with SQLite or MySQL support via `DATABASE_URL`.

**Architecture:** Sinatra modular app (unchanged structure). Sequel ORM replaces DataMapper — adapter selected from `DATABASE_URL` scheme automatically. Session auth inlined in `lib/session_auth.rb`. ERB views styled with Tailwind standalone CLI. Hotwire (Turbo + Stimulus) loaded from CDN. All models loaded once in `config.ru`. Individual app class `configure` blocks that previously loaded models and called `DataMapper.finalize` are removed.

**Tech Stack:** Ruby 3.3, Sinatra ~> 4.0, Sequel, SQLite3/MySQL2, BCrypt, mail gem, Prawn ~> 2.5 + prawn-table, Tailwind CSS (standalone CLI binary), Hotwire from CDN, ERB, Puma, dotenv, sinatra-contrib, sinatra-flash

## Global Constraints

- Ruby 3.3 — `.ruby-version` must be present, pinned to `3.3`
- `DATABASE_URL` drives adapter: `sqlite://./db/development.sqlite3` or `mysql2://user:pass@host/db`
- `.env` must never be committed — only `.env.example` is committed
- No jQuery, no HAML, no DataMapper, no ActionMailer, no Thin in final state
- Tailwind standalone CLI binary (`./tailwindcss`) at repo root, added to `.gitignore`
- Hotwire loaded from CDN only — no npm, no build pipeline
- Send Invoice UI disabled + route guarded when `SMTP_HOST` env var is absent or empty

---

## File Map

**Created:**
- `.ruby-version`
- `.env.example`
- `db/migrate.rb`
- `db/seeds.rb`
- `db/migrations/001_create_users.rb`
- `db/migrations/002_create_clients.rb`
- `db/migrations/003_create_invoices.rb`
- `db/migrations/004_create_services.rb`
- `db/migrations/005_create_divisions_categories_billing_codes.rb`
- `lib/session_auth.rb`
- `lib/mailer.rb`
- `public/css/input.css`
- `tailwind.config.js`
- `views/admin/layout.erb`
- `views/admin/layout-login.erb`
- `views/admin/layout-default.erb`
- `views/auth/login.erb`
- `views/admin/home.erb`
- `views/admin/error.erb`
- `views/admin/not_found.erb`
- `views/clients/list.erb`
- `views/clients/view.erb`
- `views/clients/create.erb`
- `views/clients/edit.erb`
- `views/invoices/list.erb`
- `views/invoices/view.erb`
- `views/invoices/create.erb`
- `views/invoices/edit.erb`
- `views/invoices/html_email.erb`
- `views/invoices/text_email.erb`

**Modified:**
- `Gemfile`
- `config.ru`
- `config/_app_settings.rb`
- `app/base.rb`
- `app/admin.rb`
- `app/auth.rb`
- `app/clients.rb`
- `app/invoices.rb`
- `models/user.rb`
- `models/models.rb`
- `Procfile`
- `.gitignore`
- `README.md`
- `scripts/send_approve_invoices.rb`

**Deleted:**
- `lib/action_mailer.rb`, `lib/prawn.rb`, `lib/thin.rb`, `lib/daemons.rb`
- `public/js/jquery-1.7.1.min.js`, `public/js/jquery.example.min.js`, `public/js/login.js`, `public/js/invoices.js`
- `public/css/style.css`, `public/css/colors.css`, `public/css/fonts.css`, `public/css/clients.css`, `public/css/css-reset.css`
- All `views/**/*.haml`

---

## Task 1: Git housekeeping + Ruby version

**Files:**
- Create: `.ruby-version`
- Modify: `.gitignore`

- [ ] **Step 1: Rename master → main**

```bash
git branch -m master main
```

- [ ] **Step 2: Create `.ruby-version`**

```
3.3
```

- [ ] **Step 3: Update `.gitignore`**

Replace entire contents:

```
.env
logs/
public/pdfs/
public/css/tailwind.css
tailwindcss
db/*.sqlite3
```

- [ ] **Step 4: Commit**

```bash
git add .ruby-version .gitignore
git commit -m "chore: rename to main, pin Ruby 3.3, update .gitignore"
```

---

## Task 2: Gemfile rewrite

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Replace `Gemfile` entirely**

```ruby
source 'https://rubygems.org'
ruby '3.3'

gem 'puma'
gem 'sinatra', '~> 4.0'
gem 'sinatra-contrib'
gem 'sinatra-flash'
gem 'rack-protection'

gem 'sequel'
gem 'sqlite3', '~> 2.0'
gem 'mysql2'

gem 'dotenv'
gem 'bcrypt'
gem 'mail'

gem 'prawn', '~> 2.5'
gem 'prawn-table'
```

- [ ] **Step 2: Install gems**

```bash
bundle install
```

Expected: all gems install without errors. If `mysql2` fails on your system (requires MySQL dev headers), add `--without mysql2` or move it to a group. SQLite is the default and all core functionality works without MySQL.

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: rewrite Gemfile for Ruby 3.3 (sequel, puma, tailwind, hotwire)"
```

---

## Task 3: dotenv configuration

**Files:**
- Create: `.env.example`
- Modify: `config/_app_settings.rb`

- [ ] **Step 1: Create `.env.example`**

```
DATABASE_URL=sqlite://./db/development.sqlite3
SESSION_SECRET=changeme_use_a_long_random_string
SMTP_HOST=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
MAIL_FROM=
RACK_ENV=development
```

- [ ] **Step 2: Create your local `.env`** (not committed)

Copy `.env.example` to `.env` and fill in at minimum:

```
DATABASE_URL=sqlite://./db/development.sqlite3
SESSION_SECRET=any_long_random_string_here
RACK_ENV=development
```

Leave SMTP vars blank for now — email send will be disabled.

- [ ] **Step 3: Replace `config/_app_settings.rb`**

```ruby
require 'dotenv'
Dotenv.load
```

- [ ] **Step 4: Commit**

```bash
git add .env.example config/_app_settings.rb
git commit -m "chore: replace hardcoded config with dotenv"
```

---

## Task 4: Sequel migrations

**Files:**
- Create: `db/migrate.rb`
- Create: `db/migrations/001_create_users.rb` through `005_...`

- [ ] **Step 1: Create `db/migrate.rb`**

```ruby
require 'dotenv'
Dotenv.load

require 'sequel'
DB = Sequel.connect(ENV.fetch('DATABASE_URL'))
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path('migrations', __dir__))
puts "Migrations complete."
```

- [ ] **Step 2: Create `db/migrations/001_create_users.rb`**

```ruby
Sequel.migration do
  up do
    create_table(:users) do
      primary_key :id
      String :login, null: false, unique: true
      String :hashed_password
      String :first_name
      String :last_name
      TrueClass :is_admin, default: false
      DateTime :lastlogin_at
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down { drop_table(:users) }
end
```

- [ ] **Step 3: Create `db/migrations/002_create_clients.rb`**

```ruby
Sequel.migration do
  up do
    create_table(:clients) do
      primary_key :id
      String :client_key, null: false, unique: true
      String :client_prefix, null: false, size: 12
      String :name, null: false
      String :contact, null: false
      String :email, null: false
      String :street, null: false
      String :street2
      String :city, null: false
      String :state, null: false
      String :zip, null: false
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down { drop_table(:clients) }
end
```

- [ ] **Step 4: Create `db/migrations/003_create_invoices.rb`**

```ruby
Sequel.migration do
  up do
    create_table(:invoices) do
      primary_key :id
      foreign_key :client_id, :clients, null: false
      String :num
      DateTime :invoice_date
      Float :total_amount, default: 0.0
      Float :total_discount, default: 0.0
      Float :amount_paid, default: 0.0
      TrueClass :is_complete, default: false
      Text :terms
      Text :notes
      DateTime :approved_on
      DateTime :sent_at
      DateTime :paid_at
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down { drop_table(:invoices) }
end
```

- [ ] **Step 5: Create `db/migrations/004_create_services.rb`**

```ruby
Sequel.migration do
  up do
    create_table(:services) do
      primary_key :id
      foreign_key :invoice_id, :invoices, null: false
      String :item
      String :desc
      DateTime :service_date
      Integer :qty
      Float :cost
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down { drop_table(:services) }
end
```

- [ ] **Step 6: Create `db/migrations/005_create_divisions_categories_billing_codes.rb`**

```ruby
Sequel.migration do
  up do
    create_table(:divisions) do
      primary_key :id
      String :name
      DateTime :created_at
      DateTime :updated_at
    end

    create_table(:categories) do
      primary_key :id
      foreign_key :division_id, :divisions
      String :name
      DateTime :created_at
      DateTime :updated_at
    end

    create_table(:billing_codes) do
      primary_key :id
      foreign_key :category_id, :categories
      String :code
      String :desc
      String :notes
      Float :rate
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down do
    drop_table(:billing_codes)
    drop_table(:categories)
    drop_table(:divisions)
  end
end
```

- [ ] **Step 7: Run migrations**

```bash
bundle exec ruby db/migrate.rb
```

Expected output: `Migrations complete.`
Verify: `ls db/` should show `development.sqlite3` (or your configured DB file).

- [ ] **Step 8: Commit**

```bash
git add db/
git commit -m "feat: add Sequel migrations for all tables"
```

---

## Task 5: Sequel models

**Files:**
- Modify: `models/user.rb`
- Modify: `models/models.rb`

- [ ] **Step 1: Replace `models/user.rb`**

```ruby
require 'bcrypt'

class User < Sequel::Model
  plugin :timestamps, update_on_create: true

  def self.authenticate(login, password)
    user = first(login: login)
    return nil unless user
    return nil unless BCrypt::Password.new(user.hashed_password) == password
    user
  end

  def password=(new_password)
    self.hashed_password = BCrypt::Password.create(new_password).to_s
  end
end
```

- [ ] **Step 2: Replace `models/models.rb`**

```ruby
module Formattable
  def format_number(n, d)
    ("%.#{d}f" % n.to_f).to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
  end
end

class Client < Sequel::Model
  include Formattable
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  one_to_many :invoices

  def validate
    super
    validates_presence [:client_key, :client_prefix, :name, :contact, :email, :street, :city, :state, :zip]
  end

  def title=(name)
    self.name = name
    self.client_key = name.gsub(/\s/, "-").gsub(/[^\w-]/, '').split("-").map { |n| n[0].chr.downcase }.join
    existing = self.class.first(client_key: self.client_key)
    self.client_key = "#{self.client_key}#{rand(100)}" if existing
  end
end

class Invoice < Sequel::Model
  include Formattable
  plugin :timestamps, update_on_create: true

  many_to_one :client
  one_to_many :services

  def formatted_invoice_num(client_obj)
    if num && !num.empty?
      num
    elsif client_obj
      last = self.class.where(client_id: client_obj.id).order(Sequel.desc(:created_at)).first
      last ? "%03d" % (last.num.to_i + 1) : "001"
    else
      "001"
    end
  end

  def formatted_invoice_date
    invoice_date ? invoice_date.strftime("%m/%d/%Y") : Time.now.strftime("%m/%d/%Y")
  end

  def formatted_total_amount
    total_amount ? format_number(total_amount, 2) : "0.00"
  end

  def formatted_total_discount
    total_discount ? format_number(total_discount, 2) : "0.00"
  end

  def formatted_discount_percentage
    format_number((total_discount.to_f / total_amount.to_f) * 100, 1)
  end

  def formatted_discount_total_amount
    format_number(total_amount.to_f - total_discount.to_f, 2)
  end

  def formatted_final_amount
    format_number(total_amount.to_f - total_discount.to_f - amount_paid.to_f, 2)
  end

  def formatted_amount_paid
    amount_paid ? format_number(amount_paid, 2) : "0.00"
  end

  def formatted_terms
    terms || "Payable upon receipt"
  end

  def formatted_notes
    notes || "Thank you for your business"
  end

  def get_status
    if paid_at
      "paid"
    elsif sent_at && Time.now > sent_at + (15 * 24 * 3600)
      "late"
    elsif sent_at
      "sent"
    elsif approved_on
      "approved"
    else
      "draft"
    end
  end

  def editable?
    sent_at.nil?
  end

  def formatted_sent_date
    sent_at ? sent_at.strftime("%m/%d/%Y %H:%M:%S") : ""
  end

  def formatted_paid_date
    paid_at ? paid_at.strftime("%m/%d/%Y %H:%M:%S") : ""
  end
end

class Service < Sequel::Model
  include Formattable
  plugin :timestamps, update_on_create: true

  many_to_one :invoice

  def formatted_service_date
    service_date ? service_date.strftime("%m/%d/%Y") : ""
  end

  def formatted_cost
    cost ? format_number(cost, 2) : ""
  end

  def formatted_line_total
    (cost && qty) ? format_number(qty * cost, 2) : ""
  end
end

class Division < Sequel::Model
  plugin :timestamps, update_on_create: true
  one_to_many :categories
end

class Category < Sequel::Model
  plugin :timestamps, update_on_create: true
  many_to_one :division
  one_to_many :billing_codes
end

class BillingCode < Sequel::Model
  plugin :timestamps, update_on_create: true
  many_to_one :category
end
```

- [ ] **Step 3: Commit**

```bash
git add models/
git commit -m "feat: migrate models from DataMapper to Sequel"
```

---

## Task 6: Auth system + seed script

**Files:**
- Create: `lib/session_auth.rb`
- Create: `db/seeds.rb`

- [ ] **Step 1: Create `lib/session_auth.rb`**

```ruby
require 'bcrypt'

module SessionAuth
  module Helpers
    def authorized?
      !!(session[:auth_user] && session[:auth_user][:id])
    end

    def authorize!
      unless authorized?
        session[:return_to] = request.path
        redirect login_url_redirect
      end
    end

    def authenticate(login, password)
      user = User.authenticate(login, password)
      if user
        session[:auth_user] = { id: user.id, is_admin: user.is_admin }
        session[:last_active_at] = Time.now.to_i
        true
      else
        false
      end
    end

    def logout!
      session.clear
    end

    def inactivity?(timeout = 3600)
      return false unless session[:last_active_at]
      Time.now.to_i - session[:last_active_at] > timeout
    end

    def current_user
      return nil unless authorized?
      User[session[:auth_user][:id]]
    end
  end
end
```

- [ ] **Step 2: Create `db/seeds.rb`**

```ruby
require 'dotenv'
Dotenv.load

require 'sequel'
require 'bcrypt'

DB = Sequel.connect(ENV.fetch('DATABASE_URL'))

require_relative '../models/user'

print "Login (email or username): "
login = $stdin.gets.chomp
print "Password: "
password = $stdin.gets.chomp
print "First name: "
first_name = $stdin.gets.chomp
print "Last name: "
last_name = $stdin.gets.chomp

User.create(
  login: login,
  hashed_password: BCrypt::Password.create(password).to_s,
  first_name: first_name,
  last_name: last_name,
  is_admin: true,
  created_at: Time.now,
  updated_at: Time.now
)

puts "Admin user '#{login}' created."
```

- [ ] **Step 3: Commit**

```bash
git add lib/session_auth.rb db/seeds.rb
git commit -m "feat: inline session auth with BCrypt, add seed script"
```

---

## Task 7: Mailer

**Files:**
- Create: `lib/mailer.rb`
- Delete: `lib/action_mailer.rb`

- [ ] **Step 1: Create `lib/mailer.rb`**

```ruby
require 'mail'

class Mailer
  def self.invoice(invoice, html_body:, text_body:, pdf_path:)
    build(
      to: invoice.client.email,
      subject: "Invoice #{invoice.client.client_prefix}-#{invoice.num}"
    ) do |m|
      m.html_part do
        content_type 'text/html; charset=UTF-8'
        body html_body
      end
      m.text_part { body text_body }
      m.add_file pdf_path if File.exist?(pdf_path)
    end
  end

  def self.build(to:, subject:, &block)
    mail = Mail.new
    mail.from    = ENV.fetch('MAIL_FROM', 'noreply@example.com')
    mail.to      = to
    mail.subject = subject
    block.call(mail)
    mail.deliver!
  end
end
```

- [ ] **Step 2: Delete old lib shims**

```bash
git rm lib/action_mailer.rb lib/prawn.rb lib/thin.rb lib/daemons.rb
```

- [ ] **Step 3: Commit**

```bash
git add lib/mailer.rb
git commit -m "feat: replace ActionMailer with mail gem wrapper"
```

---

## Task 8: config.ru + app/base.rb rewrite

**Files:**
- Modify: `config.ru`
- Modify: `app/base.rb`

- [ ] **Step 1: Replace `config.ru`**

```ruby
require 'dotenv'
Dotenv.load

require 'sequel'
DB = Sequel.connect(ENV.fetch('DATABASE_URL'))
Sequel.extension :migration

require 'mail'
if ENV['SMTP_HOST'] && !ENV['SMTP_HOST'].empty?
  Mail.defaults do
    delivery_method :smtp, {
      address:              ENV['SMTP_HOST'],
      port:                 (ENV['SMTP_PORT'] || 587).to_i,
      user_name:            ENV['SMTP_USERNAME'],
      password:             ENV['SMTP_PASSWORD'],
      enable_starttls_auto: true
    }
  end
end

$:.unshift File.expand_path('../lib', __FILE__)
$:.unshift File.expand_path('../config', __FILE__)
$:.unshift File.expand_path('../app', __FILE__)

require 'app_settings'
require 'sinatra/base'
require 'base'

require_relative 'models/user'
require_relative 'models/models'

map '/' do
  require 'admin'
  run Admin
end

map '/login' do
  require 'auth'
  run Auth
end

map '/clients' do
  require 'clients'
  run Clients
end

map '/invoices' do
  require 'invoices'
  run Invoices
end
```

- [ ] **Step 2: Replace `app/base.rb`**

```ruby
require 'json'
require 'sinatra/content_for'
require 'sinatra/flash'
require 'session_auth'

class SimplyBase < Sinatra::Base
  helpers SessionAuth::Helpers
  helpers Sinatra::ContentFor
  register Sinatra::Flash

  set :views,         File.join(File.dirname(File.dirname(__FILE__)), 'views')
  set :public_folder, File.join(File.dirname(File.dirname(__FILE__)), 'public')
  set :run,           false
  set :environment,   ENV.fetch('RACK_ENV', 'development').to_sym
  set :layout,        true
  set :logging,       true
  set :sessions,      true
  set :session_secret, ENV.fetch('SESSION_SECRET', SecureRandom.hex(64))
  set :layout_default, :'admin/layout-default'

  use Rack::Static, urls: ['/css', '/js', '/pdfs', '/favicon.ico', '/favicon.gif'], root: 'public'

  before do
    headers 'Content-Type' => 'text/html; charset=utf-8'
    session[:last_active_at] = Time.now.to_i if authorized?
  end

  configure :development do
    set :reload_templates, true
  end

  def login_url_redirect
    '/login'
  end

  def access_role?(role)
    key = :"is_#{role}"
    session[:auth_user]&.fetch(key, false) == true
  end

  def smtp_configured?
    ENV['SMTP_HOST'] && !ENV['SMTP_HOST'].empty?
  end

  def v(template, options = {})
    options[:layout] ||= settings.layout_default
    options[:layout] = false if request.xhr?
    erb(template, options)
  end

  not_found do
    @page_title = 'Not Found'
    v :'admin/not_found', layout: :'admin/layout'
  end

  error do
    @page_title = 'Error'
    v :'admin/error', layout: :'admin/layout'
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add config.ru app/base.rb
git commit -m "feat: rewrite config.ru and base.rb for Sequel + modern Sinatra"
```

---

## Task 9: App controllers

**Files:**
- Modify: `app/admin.rb`
- Modify: `app/auth.rb`
- Modify: `app/clients.rb`
- Modify: `app/invoices.rb`

- [ ] **Step 1: Replace `app/admin.rb`**

```ruby
class Admin < SimplyBase
  set :layout_default, :'admin/layout-default'

  get '/?' do
    authorize!
    @page_title = 'Dashboard'
    v :'admin/home'
  end
end
```

- [ ] **Step 2: Replace `app/auth.rb`**

```ruby
class Auth < SimplyBase
  set :layout_default, :'admin/layout-login'

  get '/' do
    if authorized?
      flash[:success] = "You are already logged in"
      redirect '/'
    end
    if inactivity?
      flash.now[:error] = "You were logged out due to inactivity"
    end
    @action_url = url("/?r=#{params[:r]}")
    @submit_value = 'Login'
    @page_title = 'Login'
    v :'auth/login'
  end

  get '/logout' do
    logout!
    flash[:success] = "You were successfully logged out!"
    redirect url('/')
  end

  post '/' do
    if params[:login][:login].empty? || params[:login][:password].empty?
      flash.now[:error] = "Please fill in all required fields"
      @action_url = url("/?r=#{params[:r]}")
      @submit_value = 'Login'
      @page_title = 'Login'
      v :'auth/login'
    elsif authenticate(params[:login][:login], params[:login][:password])
      redirect params[:r] unless params[:r].nil? || params[:r].empty?
      redirect '/'
    else
      flash.now[:error] = "Username or password was incorrect"
      @action_url = url("/?r=#{params[:r]}")
      @submit_value = 'Login'
      @page_title = 'Login'
      v :'auth/login'
    end
  end
end
```

- [ ] **Step 3: Replace `app/clients.rb`**

```ruby
class Clients < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { authorize! }

  get '/' do
    @clients = Client.all
    @page_title = 'Clients'
    v :'clients/list'
  end

  get '/view/:client_key' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    @page_title = "Client: #{@client.name}"
    v :'clients/view'
  end

  get '/edit/:client_key' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    @action_url = url("/update/#{@client.id}")
    @submit_value = 'Update'
    @page_title = "Edit #{@client.name}"
    v :'clients/edit'
  end

  post '/update/:id' do
    client = Client[params[:id].to_i]
    halt 404 unless client
    p = params[:client]
    begin
      client.update(
        client_prefix: p[:client_prefix],
        name:          p[:name],
        contact:       p[:contact],
        email:         p[:email],
        street:        p[:street],
        street2:       p[:street2],
        city:          p[:city],
        state:         p[:state],
        zip:           p[:zip]
      )
      flash[:success] = "Client updated successfully"
    rescue Sequel::ValidationFailed => e
      flash[:error] = e.message
    end
    redirect url('/')
  end

  get '/create' do
    @client = Client.new
    @action_url = url('/create')
    @submit_value = 'Create'
    @page_title = 'New Client'
    v :'clients/create'
  end

  post '/create' do
    p = params[:client]
    @client = Client.new
    @client.title = p[:name]
    @client.client_prefix = p[:client_prefix]
    @client.contact  = p[:contact]
    @client.email    = p[:email]
    @client.street   = p[:street]
    @client.street2  = p[:street2]
    @client.city     = p[:city]
    @client.state    = p[:state]
    @client.zip      = p[:zip]
    begin
      @client.save
      flash[:success] = "Client created successfully"
      redirect url('/')
    rescue Sequel::ValidationFailed => e
      flash.now[:error] = e.message
      @action_url = url('/create')
      @submit_value = 'Create'
      @page_title = 'New Client'
      v :'clients/create'
    end
  end
end
```

- [ ] **Step 4: Replace `app/invoices.rb`**

```ruby
require 'prawn'
require 'prawn/table'
require 'mailer'

class Invoices < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { authorize! }

  get '/:client_key?' do
    halt 404 unless params[:client_key]
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    @invoices = Invoice.where(client_id: @client.id).order(Sequel.desc(:id)).limit(20).all
    @page_title = "Invoices — #{@client.name}"
    v :'invoices/list'
  end

  get '/create/:client_key' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    @invoice = Invoice.new
    @services = [Service.new]
    @action_url = url("/create/#{@client.client_key}")
    @submit_value = 'Create Invoice'
    @page_title = "New Invoice — #{@client.name}"
    v :'invoices/create'
  end

  get '/edit/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    @client = @invoice.client
    @services = @invoice.services
    @services = [Service.new] if @services.empty?
    @action_url = url("/update/#{@invoice.id}")
    @submit_value = 'Update Invoice'
    @page_title = "Edit Invoice — #{@client.name}"
    v :'invoices/edit'
  end

  post '/create/:client_key' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    @invoice = Invoice.new(gather_invoice_data(params[:invoice]))
    @invoice.client = @client
    begin
      @invoice.save
    rescue Sequel::ValidationFailed => e
      flash[:error] = e.message
      redirect url("/create/#{@client.client_key}")
    end
    process_invoice_services(params[:invoice], @invoice)
    if validate_invoice(@invoice)
      create_invoice_pdf(settings.public_folder, @invoice, '/css/images/logo.png')
      flash[:success] = "Invoice created successfully"
      redirect url("/#{@invoice.client.client_key}")
    end
    flash[:error] = "Please enter all required fields"
    redirect url("/edit/#{@invoice.id}")
  end

  post '/update/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    begin
      @invoice.update(gather_invoice_data(params[:invoice]))
    rescue Sequel::ValidationFailed => e
      flash[:error] = e.message
      redirect url("/edit/#{@invoice.id}")
    end
    process_invoice_services(params[:invoice], @invoice)
    if validate_invoice(@invoice)
      create_invoice_pdf(settings.public_folder, @invoice, '/css/images/logo.png')
      flash[:success] = "Invoice updated successfully"
      redirect url("/#{@invoice.client.client_key}")
    end
    flash[:error] = "Please enter all required fields"
    redirect url("/edit/#{@invoice.id}")
  end

  get '/view/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    @logopath = '/css/images/logo.png'
    pdf_paths = get_invoice_pdf_path(settings.public_folder, @invoice)
    @pdf_invoice_path = pdf_paths[:web]
    @smtp_configured = smtp_configured?
    @page_title = "Invoice #{@invoice.num} — #{@invoice.client.name}"
    v :'invoices/view'
  end

  get '/approve/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    @invoice.update(approved_on: Time.now) if @invoice.approved_on.nil?
    flash[:success] = "Invoice approved!"
    redirect url("/view/#{@invoice.id}")
  end

  get '/send/:id' do
    unless smtp_configured?
      flash[:error] = "SMTP is not configured — cannot send email"
      redirect url("/view/#{params[:id]}")
    end
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    html_body = erb :'invoices/html_email', layout: false
    text_body = erb :'invoices/text_email', layout: false
    pdf_paths = get_invoice_pdf_path(settings.public_folder, @invoice)
    Mailer.invoice(@invoice, html_body: html_body, text_body: text_body, pdf_path: pdf_paths[:local])
    @invoice.update(sent_at: Time.now) if @invoice.sent_at.nil?
    flash[:success] = "Invoice sent successfully!"
    redirect url("/view/#{@invoice.id}")
  end

  get '/paid/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    @invoice.update(paid_at: Time.now) if @invoice.paid_at.nil?
    flash[:success] = "Invoice marked as paid!"
    redirect url("/view/#{@invoice.id}")
  end

  helpers do
    def process_invoice_services(invoice_data, invoice)
      return unless invoice_data[:services]
      invoice_data[:services].each do |_key, s|
        if s[:service_id] && !s[:service_id].empty?
          serv = Service[s[:service_id].to_i]
          serv.update(
            item:         s[:item].empty? ? nil : s[:item],
            desc:         s[:desc].empty? ? nil : s[:desc],
            service_date: s[:service_date].empty? ? nil : s[:service_date],
            qty:          s[:qty].empty? ? nil : s[:qty].to_i,
            cost:         s[:cost].empty? ? nil : s[:cost].to_f
          ) if serv
        else
          next if s[:item].empty? && s[:desc].empty?
          Service.create(
            invoice_id:   invoice.id,
            item:         s[:item].empty? ? nil : s[:item],
            desc:         s[:desc].empty? ? nil : s[:desc],
            service_date: s[:service_date].empty? ? nil : s[:service_date],
            qty:          s[:qty].empty? ? nil : s[:qty].to_i,
            cost:         s[:cost].empty? ? nil : s[:cost].to_f
          )
        end
      end

      if invoice_data[:delete_services]
        invoice_data[:delete_services].each do |id|
          Service[id.to_i]&.destroy
        end
      end
    end

    def gather_invoice_data(d)
      {
        num:            d[:num].empty? ? nil : d[:num],
        invoice_date:   d[:invoice_date].empty? ? nil : DateTime.strptime(d[:invoice_date], "%m/%d/%Y"),
        total_amount:   d[:total_amount].empty? ? 0.0 : d[:total_amount].gsub(/[^\d.]/, '').to_f,
        total_discount: d[:total_discount].empty? ? 0.0 : d[:total_discount].gsub(/[^\d.]/, '').to_f,
        amount_paid:    d[:amount_paid].empty? ? 0.0 : d[:amount_paid].gsub(/[^\d.]/, '').to_f,
        terms:          d[:terms],
        notes:          d[:notes],
        approved_on:    nil
      }
    end

    def validate_invoice(invoice)
      return false unless invoice.client_id && invoice.total_amount && invoice.num
      invoice.update(is_complete: true)
      true
    end

    def get_invoice_pdf_path(public_path, invoice)
      web_path  = "/pdfs/#{invoice.client.client_key}"
      local_dir = File.join(public_path, web_path)
      FileUtils.mkdir_p(local_dir)
      filename       = "#{invoice.client.client_prefix}-#{invoice.num}.pdf"
      {
        local:    File.join(local_dir, filename),
        web:      File.join(web_path, filename),
        web_path: web_path
      }
    end

    def create_invoice_pdf(public_path, invoice, logopath)
      paths = get_invoice_pdf_path(public_path, invoice)
      local_file = paths[:local]

      Prawn::Document.generate(local_file) do |pdf|
        logopath_local = File.join(public_path, logopath)
        address_x          = 35
        invoice_header_x   = 325
        lineheight_y       = 12
        font_size          = 9
        font_width_assumed = 5

        pdf.move_down 25
        pdf.font "Helvetica"
        pdf.font_size font_size

        pdf.text_box "EON Media Group, LLC",             at: [address_x, pdf.cursor]
        pdf.move_down lineheight_y
        pdf.text_box "1800 Camden Rd. Suite 107/123",    at: [address_x, pdf.cursor]
        pdf.move_down lineheight_y
        pdf.text_box "Charlotte, NC 28203",              at: [address_x, pdf.cursor]
        pdf.move_down lineheight_y

        last_y = pdf.cursor
        pdf.move_cursor_to pdf.bounds.height
        pdf.image logopath_local, width: 125, position: :right if File.exist?(logopath_local)
        pdf.move_cursor_to last_y

        pdf.move_down 85
        last_y = pdf.cursor

        pdf.text_box "#{invoice.client.name}",                                        at: [address_x, pdf.cursor]
        pdf.move_down lineheight_y
        pdf.text_box "#{invoice.client.contact}",                                     at: [address_x, pdf.cursor]
        pdf.move_down lineheight_y
        pdf.text_box "#{invoice.client.street} #{invoice.client.street2}",            at: [address_x, pdf.cursor]
        pdf.move_down lineheight_y
        pdf.text_box "#{invoice.client.city}, #{invoice.client.state} #{invoice.client.zip}", at: [address_x, pdf.cursor]

        pdf.move_cursor_to last_y

        header_data = [
          ["Invoice #",    "#{invoice.client.client_prefix}-#{invoice.num}"],
          ["Invoice Date", invoice.formatted_invoice_date],
          ["Balance",      "$#{invoice.formatted_final_amount} USD"]
        ]
        pdf.table(header_data, position: invoice_header_x, width: 215) do
          style(row(0..1).columns(0..1), padding: [2, 5, 2, 5], borders: [])
          style(row(2), background_color: 'e9e9e9', border_color: 'dddddd', font_style: :bold)
          style(column(1), align: :right)
          style(row(2).columns(0), borders: [:top, :left, :bottom])
          style(row(2).columns(1), borders: [:top, :right, :bottom])
        end

        pdf.move_down 45

        service_data = [["Item", "Description", "Unit Cost", "Quantity", "Line Total"]]
        invoice.services.each do |s|
          service_data << [s.item.to_s, s.desc.to_s, "$#{s.formatted_cost}", s.qty.to_s, "$#{s.formatted_line_total}"]
        end
        service_data << [" ", " ", " ", " ", " "]

        pdf.table(service_data, width: pdf.bounds.width) do
          style(row(1..-1).columns(0..-1), padding: [4, 5, 4, 5], borders: [:bottom], border_color: 'dddddd')
          style(row(0), background_color: 'e9e9e9', border_color: 'dddddd', font_style: :bold)
          style(row(0).columns(0..-1), borders: [:top, :bottom])
          style(row(0).columns(0),  borders: [:top, :left, :bottom])
          style(row(0).columns(-1), borders: [:top, :right, :bottom])
          style(row(-1), border_width: 2)
          style(column(2..-1), align: :right)
          style(columns(0), width: 75)
          style(columns(1), width: 275)
        end

        pdf.move_down 1

        totals = []
        if invoice.total_discount.to_f > 0
          totals << ["Sub Total",      "$#{invoice.formatted_total_amount}"]
          totals << ["Discount -#{invoice.formatted_discount_percentage}%", "$#{invoice.formatted_total_discount}"]
          totals << ["Invoice Total",  "$#{invoice.formatted_discount_total_amount}"]
        else
          totals << ["Invoice Total",  "$#{invoice.formatted_total_amount}"]
        end
        totals << ["Amount Paid", "-$#{invoice.formatted_amount_paid}"]
        totals << ["Balance",     "$#{invoice.formatted_final_amount} USD"]

        pdf.table(totals, position: invoice_header_x, width: 215) do
          style(row(0), font_style: :bold)
          style(column(1), align: :right)
          if invoice.total_discount.to_f > 0
            style(row(0..3).columns(0..3), padding: [2, 5, 2, 5], borders: [])
            style(row(2), font_style: :bold, border_color: 'dddddd', borders: [:top])
            style(row(4), background_color: 'e9e9e9', border_color: 'dddddd', font_style: :bold)
            style(row(4).columns(0), borders: [:top, :left, :bottom])
            style(row(4).columns(1), borders: [:top, :right, :bottom])
          else
            style(row(0..1).columns(0..1), padding: [2, 5, 2, 5], borders: [])
            style(row(2), background_color: 'e9e9e9', border_color: 'dddddd', font_style: :bold)
            style(row(2).columns(0), borders: [:top, :left, :bottom])
            style(row(2).columns(1), borders: [:top, :right, :bottom])
          end
        end

        pdf.move_down 25

        pdf.table([["Terms"], [invoice.formatted_terms]], width: 275) do
          style(row(0..-1).columns(0..-1), padding: [1, 0, 1, 0], borders: [])
          style(row(0).columns(0), font_style: :bold)
        end

        pdf.move_down 15

        pdf.table([["Notes"], [invoice.formatted_notes]], width: 275) do
          style(row(0..-1).columns(0..-1), padding: [1, 0, 1, 0], borders: [])
          style(row(0).columns(0), font_style: :bold)
        end

        page_num = "page 1 of 1"
        pdf.text_box page_num, at: [(pdf.bounds.width - (page_num.length * font_width_assumed)), 10]
      end

      paths[:web]
    end
  end
end
```

- [ ] **Step 5: Commit**

```bash
git add app/
git commit -m "feat: update all app controllers to Sequel + new auth/mailer"
```

---

## Task 10: Tailwind CSS setup

**Files:**
- Create: `tailwind.config.js`
- Create: `public/css/input.css`
- Download: `./tailwindcss` binary

- [ ] **Step 1: Download the Tailwind standalone CLI**

```bash
curl -sLO https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-linux-x64
chmod +x tailwindcss-linux-x64
mv tailwindcss-linux-x64 tailwindcss
```

The binary is already in `.gitignore` as `tailwindcss`.

- [ ] **Step 2: Create `tailwind.config.js`**

```js
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./views/**/*.erb",
    "./app/**/*.rb",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

- [ ] **Step 3: Create `public/css/input.css`**

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

- [ ] **Step 4: Build Tailwind for the first time**

```bash
./tailwindcss -i public/css/input.css -o public/css/tailwind.css
```

Expected: `public/css/tailwind.css` is created.

- [ ] **Step 5: Delete old CSS files**

```bash
git rm public/css/style.css public/css/colors.css public/css/fonts.css public/css/clients.css public/css/css-reset.css
```

- [ ] **Step 6: Commit**

```bash
git add tailwind.config.js public/css/input.css public/css/tailwind.css
git commit -m "feat: add Tailwind CSS standalone CLI setup"
```

---

## Task 11: ERB layouts

**Files:**
- Create: `views/admin/layout.erb` (for error/not_found pages)
- Create: `views/admin/layout-login.erb` (for login page)
- Create: `views/admin/layout-default.erb` (main app layout with sidebar)

- [ ] **Step 1: Create `views/admin/layout-login.erb`**

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= @page_title ? "#{@page_title} — Simply Suite" : "Simply Suite" %></title>
  <link rel="stylesheet" href="/css/tailwind.css">
</head>
<body class="min-h-screen bg-slate-800 flex items-center justify-center p-4">
  <div class="w-full max-w-md">
    <% if flash[:error] %>
      <div class="mb-4 p-4 bg-red-50 border border-red-200 text-red-800 rounded-lg text-sm"><%= flash[:error] %></div>
    <% end %>
    <% if flash[:success] %>
      <div class="mb-4 p-4 bg-green-50 border border-green-200 text-green-800 rounded-lg text-sm"><%= flash[:success] %></div>
    <% end %>
    <%= yield %>
  </div>
</body>
</html>
```

- [ ] **Step 2: Create `views/admin/layout-default.erb`**

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= @page_title ? "#{@page_title} — Simply Suite" : "Simply Suite" %></title>
  <link rel="stylesheet" href="/css/tailwind.css">
</head>
<body class="bg-gray-50 text-gray-900 h-screen flex overflow-hidden">

  <!-- Sidebar -->
  <aside class="w-56 bg-slate-800 text-white flex flex-col flex-shrink-0">
    <div class="px-5 py-4 border-b border-slate-700">
      <span class="text-base font-semibold tracking-tight">Simply Suite</span>
    </div>
    <nav class="flex-1 px-3 py-4 space-y-1">
      <a href="/" class="flex items-center px-3 py-2 rounded-md text-sm font-medium text-slate-300 hover:bg-slate-700 hover:text-white transition-colors">
        Dashboard
      </a>
      <a href="/clients" class="flex items-center px-3 py-2 rounded-md text-sm font-medium text-slate-300 hover:bg-slate-700 hover:text-white transition-colors">
        Clients
      </a>
    </nav>
    <div class="px-5 py-4 border-t border-slate-700">
      <a href="/login/logout" class="text-xs text-slate-400 hover:text-white transition-colors">Sign out</a>
    </div>
  </aside>

  <!-- Main -->
  <div class="flex-1 flex flex-col overflow-hidden">
    <header class="bg-white border-b border-gray-200 px-6 py-3 flex items-center justify-between flex-shrink-0">
      <h1 class="text-base font-semibold text-gray-800"><%= @page_title || 'Simply Suite' %></h1>
    </header>

    <main class="flex-1 overflow-auto p-6">
      <% if flash[:success] %>
        <div class="mb-5 p-4 bg-green-50 border border-green-200 text-green-800 rounded-lg text-sm"><%= flash[:success] %></div>
      <% end %>
      <% if flash[:error] %>
        <div class="mb-5 p-4 bg-red-50 border border-red-200 text-red-800 rounded-lg text-sm"><%= flash[:error] %></div>
      <% end %>
      <%= yield %>
    </main>
  </div>

  <script type="module">
    import * as Turbo from 'https://cdn.jsdelivr.net/npm/@hotwired/turbo@8/dist/turbo.es2017.esm.js';
    import { Application, Controller } from 'https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3/dist/stimulus.js';

    const app = Application.start();

    class InvoiceFormController extends Controller {
      static targets = ['servicesContainer', 'serviceTemplate', 'form']

      connect() {
        this.serviceIndex = this.servicesContainerTarget.querySelectorAll('[data-service-row]').length;
      }

      addService(event) {
        event.preventDefault();
        const html = this.serviceTemplateTarget.innerHTML.replace(/SERVICE_INDEX/g, this.serviceIndex++);
        this.servicesContainerTarget.insertAdjacentHTML('beforeend', html);
      }

      removeService(event) {
        event.preventDefault();
        const row = event.target.closest('[data-service-row]');
        const idInput = row.querySelector('input[name*="[service_id]"]');
        if (idInput && idInput.value) {
          const hidden = document.createElement('input');
          hidden.type = 'hidden';
          hidden.name = 'invoice[delete_services][]';
          hidden.value = idInput.value;
          this.formTarget.appendChild(hidden);
        }
        row.remove();
      }
    }

    app.register('invoice-form', InvoiceFormController);
  </script>
</body>
</html>
```

- [ ] **Step 3: Create `views/admin/layout.erb`** (minimal, for error pages)

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= @page_title ? "#{@page_title} — Simply Suite" : "Simply Suite" %></title>
  <link rel="stylesheet" href="/css/tailwind.css">
</head>
<body class="bg-gray-50 text-gray-900 flex items-center justify-center min-h-screen">
  <div class="max-w-lg w-full p-8">
    <%= yield %>
  </div>
</body>
</html>
```

- [ ] **Step 4: Commit**

```bash
git add views/admin/layout.erb views/admin/layout-login.erb views/admin/layout-default.erb
git commit -m "feat: add ERB layouts with Tailwind + Hotwire Stimulus"
```

---

## Task 12: Auth + Admin ERB views

**Files:**
- Create: `views/auth/login.erb`
- Create: `views/admin/home.erb`
- Create: `views/admin/error.erb`
- Create: `views/admin/not_found.erb`

- [ ] **Step 1: Create `views/auth/login.erb`**

```erb
<div class="bg-white rounded-xl shadow-xl p-8">
  <div class="mb-8 text-center">
    <h2 class="text-2xl font-bold text-gray-900">Simply Suite</h2>
    <p class="mt-1 text-sm text-gray-500">Sign in to continue</p>
  </div>
  <form action="<%= @action_url %>" method="post" class="space-y-5">
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">Username</label>
      <input type="text" name="login[login]" required placeholder="Username"
        class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-slate-500 focus:border-slate-500 text-sm">
    </div>
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">Password</label>
      <input type="password" name="login[password]" required placeholder="Password"
        class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-slate-500 focus:border-slate-500 text-sm">
    </div>
    <button type="submit"
      class="w-full py-2 px-4 bg-slate-700 hover:bg-slate-800 text-white text-sm font-medium rounded-md transition-colors">
      <%= @submit_value %>
    </button>
  </form>
</div>
```

- [ ] **Step 2: Create `views/admin/home.erb`**

```erb
<div class="grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-2xl">
  <a href="/clients"
    class="block p-6 bg-white rounded-xl border border-gray-200 hover:border-slate-400 hover:shadow-sm transition-all">
    <h3 class="text-sm font-semibold text-gray-900">Clients</h3>
    <p class="mt-1 text-xs text-gray-500">Manage your client list and invoices</p>
  </a>
</div>
```

- [ ] **Step 3: Create `views/admin/not_found.erb`**

```erb
<div class="text-center">
  <p class="text-6xl font-bold text-gray-200">404</p>
  <h2 class="mt-4 text-xl font-semibold text-gray-700">Page not found</h2>
  <a href="/" class="mt-6 inline-block text-sm text-slate-600 hover:text-slate-900 underline">Go to dashboard</a>
</div>
```

- [ ] **Step 4: Create `views/admin/error.erb`**

```erb
<div class="text-center">
  <p class="text-6xl font-bold text-gray-200">500</p>
  <h2 class="mt-4 text-xl font-semibold text-gray-700">Something went wrong</h2>
  <% if env['sinatra.error'] %>
    <pre class="mt-4 text-left text-xs bg-gray-100 p-4 rounded overflow-auto max-h-64"><%= env['sinatra.error'].message %></pre>
  <% end %>
  <a href="/" class="mt-6 inline-block text-sm text-slate-600 hover:text-slate-900 underline">Go to dashboard</a>
</div>
```

- [ ] **Step 5: Commit**

```bash
git add views/auth/ views/admin/home.erb views/admin/error.erb views/admin/not_found.erb
git commit -m "feat: add auth and admin ERB views"
```

---

## Task 13: Client ERB views

**Files:**
- Create: `views/clients/list.erb`
- Create: `views/clients/view.erb`
- Create: `views/clients/create.erb`
- Create: `views/clients/edit.erb`

Helper partial used by create/edit — defined inline using ERB's `content_for`:

- [ ] **Step 1: Create `views/clients/list.erb`**

```erb
<div class="flex items-center justify-between mb-5">
  <div></div>
  <a href="/clients/create"
    class="px-4 py-2 bg-slate-700 hover:bg-slate-800 text-white text-sm font-medium rounded-md transition-colors">
    New Client
  </a>
</div>

<div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
  <% if @clients.empty? %>
    <p class="p-8 text-center text-sm text-gray-500">No clients yet. <a href="/clients/create" class="underline text-slate-600">Create one.</a></p>
  <% else %>
    <table class="w-full text-sm">
      <thead class="bg-gray-50 border-b border-gray-200">
        <tr>
          <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
          <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Contact</th>
          <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Email</th>
          <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100">
        <% @clients.each do |client| %>
          <tr class="hover:bg-gray-50">
            <td class="px-4 py-3 font-medium text-gray-900"><%= client.name %></td>
            <td class="px-4 py-3 text-gray-600"><%= client.contact %></td>
            <td class="px-4 py-3 text-gray-600"><%= client.email %></td>
            <td class="px-4 py-3 text-right space-x-3">
              <a href="/invoices/<%= client.client_key %>" class="text-xs text-slate-600 hover:text-slate-900 font-medium">Invoices</a>
              <a href="/clients/view/<%= client.client_key %>" class="text-xs text-slate-600 hover:text-slate-900 font-medium">View</a>
              <a href="/clients/edit/<%= client.client_key %>" class="text-xs text-slate-600 hover:text-slate-900 font-medium">Edit</a>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>
</div>
```

- [ ] **Step 2: Create `views/clients/view.erb`**

```erb
<div class="max-w-2xl space-y-6">
  <div class="flex gap-3">
    <a href="/clients/edit/<%= @client.client_key %>"
      class="px-4 py-2 bg-slate-700 hover:bg-slate-800 text-white text-sm font-medium rounded-md transition-colors">Edit</a>
    <a href="/invoices/<%= @client.client_key %>"
      class="px-4 py-2 bg-white border border-gray-300 hover:border-gray-400 text-gray-700 text-sm font-medium rounded-md transition-colors">Invoices</a>
  </div>

  <div class="bg-white rounded-xl border border-gray-200 divide-y divide-gray-100">
    <% {
      'Client Key'   => @client.client_key,
      'Prefix'       => @client.client_prefix,
      'Name'         => @client.name,
      'Contact'      => @client.contact,
      'Email'        => @client.email,
      'Street'       => [@client.street, @client.street2].reject(&:nil?).join(', '),
      'City'         => @client.city,
      'State'        => @client.state,
      'ZIP'          => @client.zip,
    }.each do |label, value| %>
      <div class="px-5 py-3 flex">
        <span class="w-32 text-xs font-medium text-gray-500 uppercase tracking-wider pt-0.5"><%= label %></span>
        <span class="text-sm text-gray-900"><%= value %></span>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: Create `views/clients/_form.erb`** (shared partial)

```erb
<div class="max-w-2xl">
  <form action="<%= @action_url %>" method="post" class="bg-white rounded-xl border border-gray-200 divide-y divide-gray-100">
    <% [
      ['Client Name',   'name',          'text',  @client.name],
      ['Client Prefix', 'client_prefix', 'text',  @client.client_prefix],
      ['Contact',       'contact',       'text',  @client.contact],
      ['Email',         'email',         'email', @client.email],
      ['Street',        'street',        'text',  @client.street],
      ['Street 2',      'street2',       'text',  @client.street2],
      ['City',          'city',          'text',  @client.city],
      ['State',         'state',         'text',  @client.state],
      ['ZIP',           'zip',           'text',  @client.zip],
    ].each do |label, field, type, val| %>
      <div class="px-5 py-4 flex items-center gap-4">
        <label class="w-32 text-xs font-medium text-gray-500 uppercase tracking-wider flex-shrink-0"><%= label %></label>
        <input type="<%= type %>" name="client[<%= field %>]" value="<%= val %>"
          class="flex-1 px-3 py-1.5 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-slate-500 focus:border-slate-500">
      </div>
    <% end %>
    <div class="px-5 py-4">
      <button type="submit"
        class="px-5 py-2 bg-slate-700 hover:bg-slate-800 text-white text-sm font-medium rounded-md transition-colors">
        <%= @submit_value %>
      </button>
    </div>
  </form>
</div>
```

- [ ] **Step 4: Create `views/clients/create.erb`**

```erb
<%= erb :'clients/_form' %>
```

- [ ] **Step 5: Create `views/clients/edit.erb`**

```erb
<%= erb :'clients/_form' %>
```

- [ ] **Step 6: Commit**

```bash
git add views/clients/
git commit -m "feat: add client ERB views with Tailwind"
```

---

## Task 14: Invoice ERB views + Stimulus

**Files:**
- Create: `views/invoices/list.erb`
- Create: `views/invoices/view.erb`
- Create: `views/invoices/create.erb`
- Create: `views/invoices/edit.erb`
- Create: `views/invoices/html_email.erb`
- Create: `views/invoices/text_email.erb`

- [ ] **Step 1: Create `views/invoices/list.erb`**

```erb
<div class="flex items-center justify-between mb-5">
  <a href="/clients" class="text-sm text-slate-600 hover:text-slate-900">&larr; All Clients</a>
  <a href="/invoices/create/<%= @client.client_key %>"
    class="px-4 py-2 bg-slate-700 hover:bg-slate-800 text-white text-sm font-medium rounded-md transition-colors">
    New Invoice
  </a>
</div>

<div class="mb-4">
  <p class="text-sm text-gray-500">Client: <span class="font-medium text-gray-900"><%= @client.name %></span></p>
</div>

<% STATUS_COLORS = { 'paid' => 'bg-green-100 text-green-800', 'late' => 'bg-red-100 text-red-800',
    'sent' => 'bg-blue-100 text-blue-800', 'approved' => 'bg-yellow-100 text-yellow-800',
    'draft' => 'bg-gray-100 text-gray-700' } unless defined?(STATUS_COLORS) %>

<div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
  <% if @invoices.empty? %>
    <p class="p-8 text-center text-sm text-gray-500">No invoices yet.</p>
  <% else %>
    <table class="w-full text-sm">
      <thead class="bg-gray-50 border-b border-gray-200">
        <tr>
          <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Invoice #</th>
          <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Date</th>
          <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Balance</th>
          <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
          <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100">
        <% @invoices.each do |inv| %>
          <tr class="hover:bg-gray-50">
            <td class="px-4 py-3 font-medium"><%= @client.client_prefix %>-<%= inv.num %></td>
            <td class="px-4 py-3 text-gray-600"><%= inv.formatted_invoice_date %></td>
            <td class="px-4 py-3 text-gray-900">$<%= inv.formatted_final_amount %></td>
            <td class="px-4 py-3">
              <span class="px-2 py-0.5 rounded text-xs font-medium <%= STATUS_COLORS[inv.get_status] %>">
                <%= inv.get_status %>
              </span>
            </td>
            <td class="px-4 py-3 text-right">
              <a href="/invoices/view/<%= inv.id %>" class="text-xs text-slate-600 hover:text-slate-900 font-medium">View</a>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>
</div>
```

- [ ] **Step 2: Create `views/invoices/view.erb`**

```erb
<% STATUS_COLORS = { 'paid' => 'bg-green-100 text-green-800', 'late' => 'bg-red-100 text-red-800',
    'sent' => 'bg-blue-100 text-blue-800', 'approved' => 'bg-yellow-100 text-yellow-800',
    'draft' => 'bg-gray-100 text-gray-700' } unless defined?(STATUS_COLORS) %>

<div class="max-w-3xl space-y-5">
  <!-- Actions -->
  <div class="flex flex-wrap gap-2">
    <a href="/invoices/<%= @invoice.client.client_key %>"
      class="px-3 py-1.5 bg-white border border-gray-300 hover:border-gray-400 text-gray-700 text-xs font-medium rounded-md">&larr; Back</a>
    <% if @invoice.editable? %>
      <a href="/invoices/edit/<%= @invoice.id %>"
        class="px-3 py-1.5 bg-white border border-gray-300 hover:border-gray-400 text-gray-700 text-xs font-medium rounded-md">Edit</a>
    <% end %>
    <% if @invoice.approved_on.nil? %>
      <a href="/invoices/approve/<%= @invoice.id %>"
        class="px-3 py-1.5 bg-white border border-gray-300 hover:border-gray-400 text-gray-700 text-xs font-medium rounded-md">Approve</a>
    <% end %>
    <% if !@invoice.approved_on.nil? && @invoice.sent_at.nil? %>
      <% if @smtp_configured %>
        <a href="/invoices/send/<%= @invoice.id %>"
          class="px-3 py-1.5 bg-slate-700 hover:bg-slate-800 text-white text-xs font-medium rounded-md">Send</a>
      <% else %>
        <span title="SMTP not configured — set SMTP_HOST in .env to enable"
          class="px-3 py-1.5 bg-gray-200 text-gray-400 text-xs font-medium rounded-md cursor-not-allowed">Send (SMTP not configured)</span>
      <% end %>
    <% end %>
    <% if @invoice.paid_at.nil? && !@invoice.sent_at.nil? %>
      <a href="/invoices/paid/<%= @invoice.id %>"
        class="px-3 py-1.5 bg-green-600 hover:bg-green-700 text-white text-xs font-medium rounded-md">Mark Paid</a>
    <% end %>
    <% unless @pdf_invoice_path.nil? %>
      <a href="<%= @pdf_invoice_path %>" target="_blank"
        class="px-3 py-1.5 bg-white border border-gray-300 hover:border-gray-400 text-gray-700 text-xs font-medium rounded-md">PDF</a>
    <% end %>
  </div>

  <!-- Summary card -->
  <div class="bg-white rounded-xl border border-gray-200 divide-y divide-gray-100">
    <div class="px-5 py-4 flex items-center justify-between">
      <div>
        <p class="text-xs text-gray-500">Invoice</p>
        <p class="text-lg font-semibold"><%= @invoice.client.client_prefix %>-<%= @invoice.num %></p>
      </div>
      <span class="px-2.5 py-1 rounded-full text-xs font-medium <%= STATUS_COLORS[@invoice.get_status] %>">
        <%= @invoice.get_status %>
      </span>
    </div>
    <% {
      'Client'       => @invoice.client.name,
      'Date'         => @invoice.formatted_invoice_date,
      'Total'        => "$#{@invoice.formatted_total_amount}",
      'Discount'     => @invoice.total_discount.to_f > 0 ? "$#{@invoice.formatted_total_discount} (#{@invoice.formatted_discount_percentage}%)" : '—',
      'Amount Paid'  => "$#{@invoice.formatted_amount_paid}",
      'Balance'      => "$#{@invoice.formatted_final_amount} USD",
      'Terms'        => @invoice.formatted_terms,
      'Approved'     => @invoice.approved_on ? @invoice.approved_on.strftime("%m/%d/%Y") : '—',
      'Sent'         => @invoice.formatted_sent_date.empty? ? '—' : @invoice.formatted_sent_date,
      'Paid'         => @invoice.formatted_paid_date.empty? ? '—' : @invoice.formatted_paid_date,
    }.each do |label, value| %>
      <div class="px-5 py-3 flex">
        <span class="w-32 text-xs font-medium text-gray-500 uppercase tracking-wider pt-0.5"><%= label %></span>
        <span class="text-sm text-gray-900"><%= value %></span>
      </div>
    <% end %>
  </div>

  <!-- Services -->
  <div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
    <table class="w-full text-sm">
      <thead class="bg-gray-50 border-b border-gray-200">
        <tr>
          <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Item</th>
          <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Description</th>
          <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Unit Cost</th>
          <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Qty</th>
          <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Line Total</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-100">
        <% @invoice.services.each do |s| %>
          <tr>
            <td class="px-4 py-3"><%= s.item %></td>
            <td class="px-4 py-3 text-gray-600"><%= s.desc %></td>
            <td class="px-4 py-3 text-right">$<%= s.formatted_cost %></td>
            <td class="px-4 py-3 text-right"><%= s.qty %></td>
            <td class="px-4 py-3 text-right font-medium">$<%= s.formatted_line_total %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

- [ ] **Step 3: Create `views/invoices/_service_row.erb`** (Stimulus template partial)

This template is rendered once hidden, then cloned by the Stimulus controller. `SERVICE_INDEX` is replaced by JS.

```erb
<div class="grid grid-cols-12 gap-2 items-center py-2 border-b border-gray-100" data-service-row>
  <input type="hidden" name="invoice[services][SERVICE_INDEX][service_id]" value="">
  <input type="text"   name="invoice[services][SERVICE_INDEX][item]"
    placeholder="Item"
    class="col-span-2 px-2 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-1 focus:ring-slate-500">
  <input type="text"   name="invoice[services][SERVICE_INDEX][desc]"
    placeholder="Description"
    class="col-span-4 px-2 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-1 focus:ring-slate-500">
  <input type="text"   name="invoice[services][SERVICE_INDEX][service_date]"
    placeholder="MM/DD/YYYY"
    class="col-span-2 px-2 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-1 focus:ring-slate-500">
  <input type="number" name="invoice[services][SERVICE_INDEX][qty]"
    placeholder="Qty"
    class="col-span-1 px-2 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-1 focus:ring-slate-500">
  <input type="text"   name="invoice[services][SERVICE_INDEX][cost]"
    placeholder="0.00"
    class="col-span-2 px-2 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-1 focus:ring-slate-500">
  <button type="button" data-action="invoice-form#removeService"
    class="col-span-1 text-gray-400 hover:text-red-500 text-xs text-right transition-colors">&times; Remove</button>
</div>
```

- [ ] **Step 4: Create `views/invoices/_form.erb`**

```erb
<div class="max-w-3xl" data-controller="invoice-form">
  <form action="<%= @action_url %>" method="post" data-invoice-form-target="form">

    <!-- Invoice header fields -->
    <div class="bg-white rounded-xl border border-gray-200 divide-y divide-gray-100 mb-5">
      <% [
        ['Invoice #',     'num',            'text',   @invoice.formatted_invoice_num(@client)],
        ['Date',          'invoice_date',   'text',   @invoice.formatted_invoice_date],
        ['Total Amount',  'total_amount',   'text',   @invoice.formatted_total_amount],
        ['Discount',      'total_discount', 'text',   @invoice.formatted_total_discount],
        ['Amount Paid',   'amount_paid',    'text',   @invoice.formatted_amount_paid],
        ['Terms',         'terms',          'text',   @invoice.formatted_terms],
        ['Notes',         'notes',          'text',   @invoice.formatted_notes],
      ].each do |label, field, type, val| %>
        <div class="px-5 py-3 flex items-center gap-4">
          <label class="w-36 text-xs font-medium text-gray-500 uppercase tracking-wider flex-shrink-0"><%= label %></label>
          <input type="<%= type %>" name="invoice[<%= field %>]" value="<%= val %>"
            class="flex-1 px-3 py-1.5 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-slate-500 focus:border-slate-500">
        </div>
      <% end %>
    </div>

    <!-- Services -->
    <div class="bg-white rounded-xl border border-gray-200 p-5 mb-5">
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-gray-700">Services</h3>
        <button type="button" data-action="invoice-form#addService"
          class="px-3 py-1 bg-white border border-gray-300 hover:border-slate-500 text-xs font-medium rounded transition-colors">
          + Add Line
        </button>
      </div>

      <div class="grid grid-cols-12 gap-2 pb-2 border-b border-gray-200 mb-1">
        <span class="col-span-2 text-xs font-medium text-gray-500 uppercase">Item</span>
        <span class="col-span-4 text-xs font-medium text-gray-500 uppercase">Description</span>
        <span class="col-span-2 text-xs font-medium text-gray-500 uppercase">Date</span>
        <span class="col-span-1 text-xs font-medium text-gray-500 uppercase">Qty</span>
        <span class="col-span-2 text-xs font-medium text-gray-500 uppercase">Cost</span>
        <span class="col-span-1"></span>
      </div>

      <div data-invoice-form-target="servicesContainer">
        <% @services.each_with_index do |s, i| %>
          <div class="grid grid-cols-12 gap-2 items-center py-2 border-b border-gray-100" data-service-row>
            <input type="hidden" name="invoice[services][<%= i %>][service_id]" value="<%= s.id %>">
            <input type="text"   name="invoice[services][<%= i %>][item]" value="<%= s.item %>"
              placeholder="Item"
              class="col-span-2 px-2 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-1 focus:ring-slate-500">
            <input type="text"   name="invoice[services][<%= i %>][desc]" value="<%= s.desc %>"
              placeholder="Description"
              class="col-span-4 px-2 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-1 focus:ring-slate-500">
            <input type="text"   name="invoice[services][<%= i %>][service_date]" value="<%= s.formatted_service_date %>"
              placeholder="MM/DD/YYYY"
              class="col-span-2 px-2 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-1 focus:ring-slate-500">
            <input type="number" name="invoice[services][<%= i %>][qty]" value="<%= s.qty %>"
              placeholder="Qty"
              class="col-span-1 px-2 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-1 focus:ring-slate-500">
            <input type="text"   name="invoice[services][<%= i %>][cost]" value="<%= s.formatted_cost %>"
              placeholder="0.00"
              class="col-span-2 px-2 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-1 focus:ring-slate-500">
            <button type="button" data-action="invoice-form#removeService"
              class="col-span-1 text-gray-400 hover:text-red-500 text-xs text-right transition-colors">&times;</button>
          </div>
        <% end %>
      </div>

      <!-- Hidden Stimulus template -->
      <template data-invoice-form-target="serviceTemplate">
        <%= erb :'invoices/_service_row' %>
      </template>
    </div>

    <button type="submit"
      class="px-5 py-2 bg-slate-700 hover:bg-slate-800 text-white text-sm font-medium rounded-md transition-colors">
      <%= @submit_value %>
    </button>
  </form>
</div>
```

- [ ] **Step 5: Create `views/invoices/create.erb`**

```erb
<%= erb :'invoices/_form' %>
```

- [ ] **Step 6: Create `views/invoices/edit.erb`**

```erb
<%= erb :'invoices/_form' %>
```

- [ ] **Step 7: Create `views/invoices/html_email.erb`**

```erb
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family: Helvetica, Arial, sans-serif; font-size: 14px; color: #333;">
  <h2>Invoice <%= @invoice.client.client_prefix %>-<%= @invoice.num %></h2>
  <p>Dear <%= @invoice.client.contact %>,</p>
  <p>Please find your invoice attached. Details below:</p>
  <table style="border-collapse: collapse; width: 100%; max-width: 500px;">
    <tr><td style="padding: 4px 8px; font-weight: bold;">Invoice #</td><td style="padding: 4px 8px;"><%= @invoice.client.client_prefix %>-<%= @invoice.num %></td></tr>
    <tr><td style="padding: 4px 8px; font-weight: bold;">Date</td><td style="padding: 4px 8px;"><%= @invoice.formatted_invoice_date %></td></tr>
    <tr><td style="padding: 4px 8px; font-weight: bold;">Balance Due</td><td style="padding: 4px 8px;">$<%= @invoice.formatted_final_amount %> USD</td></tr>
    <tr><td style="padding: 4px 8px; font-weight: bold;">Terms</td><td style="padding: 4px 8px;"><%= @invoice.formatted_terms %></td></tr>
  </table>
  <p style="margin-top: 24px;"><%= @invoice.formatted_notes %></p>
</body>
</html>
```

- [ ] **Step 8: Create `views/invoices/text_email.erb`**

```
Invoice <%= @invoice.client.client_prefix %>-<%= @invoice.num %>

Dear <%= @invoice.client.contact %>,

Please find your invoice attached.

Invoice #:    <%= @invoice.client.client_prefix %>-<%= @invoice.num %>
Date:         <%= @invoice.formatted_invoice_date %>
Balance Due:  $<%= @invoice.formatted_final_amount %> USD
Terms:        <%= @invoice.formatted_terms %>

<%= @invoice.formatted_notes %>
```

- [ ] **Step 9: Commit**

```bash
git add views/invoices/
git commit -m "feat: add invoice ERB views with Stimulus form controller"
```

---

## Task 15: Cleanup + scripts + Procfile + README

**Files:**
- Modify: `Procfile`
- Modify: `scripts/send_approve_invoices.rb`
- Modify: `README.md`
- Delete: old JS, old HAML views

- [ ] **Step 1: Delete old JS files**

```bash
git rm public/js/jquery-1.7.1.min.js public/js/jquery.example.min.js public/js/login.js public/js/invoices.js
```

- [ ] **Step 2: Delete old HAML views**

```bash
git rm views/auth/login.haml views/auth/header.haml views/auth/text_email_forgot.haml views/auth/html_email_forgot.haml views/auth/register.haml views/auth/forgot.haml
git rm views/clients/create.haml views/clients/view.haml views/clients/list.haml views/clients/edit.haml
git rm views/invoices/create.haml views/invoices/view.haml views/invoices/html_email.haml views/invoices/text_email.haml views/invoices/list.haml views/invoices/edit.haml
git rm views/admin/error.haml views/admin/layout-default.haml views/admin/header.haml views/admin/layout.haml views/admin/home.haml views/admin/not_found.haml views/admin/layout-login.haml
git rm views/shared/aside.haml views/shared/header.haml views/shared/footer.haml views/shared/banner.haml views/shared/nav.haml
```

- [ ] **Step 3: Update `Procfile`**

```
web: bundle exec puma -p 9393
css: ./tailwindcss -i public/css/input.css -o public/css/tailwind.css --watch
```

- [ ] **Step 4: Replace `scripts/send_approve_invoices.rb`**

```ruby
root = File.dirname(File.dirname(__FILE__))
$:.unshift File.join(root, 'lib')
$:.unshift File.join(root, 'config')

require 'dotenv'
Dotenv.load(File.join(root, '.env'))

require 'sequel'
DB = Sequel.connect(ENV.fetch('DATABASE_URL'))

require 'mail'
if ENV['SMTP_HOST'] && !ENV['SMTP_HOST'].empty?
  Mail.defaults do
    delivery_method :smtp, {
      address:              ENV['SMTP_HOST'],
      port:                 (ENV['SMTP_PORT'] || 587).to_i,
      user_name:            ENV['SMTP_USERNAME'],
      password:             ENV['SMTP_PASSWORD'],
      enable_starttls_auto: true
    }
  end
end

require_relative '../models/models'
require 'mailer'

views_root = File.join(root, 'views')

puts "Started: #{Time.now.strftime("%m/%d/%Y %H:%M:%S")}"

invoices = Invoice.where(
  is_complete: true,
  sent_at: nil,
  paid_at: nil
).exclude(approved_on: nil).where { invoice_date < Time.now }.all

if invoices.empty?
  puts "None to process."
else
  invoices.each do |invoice|
    ctx = Object.new
    ctx.instance_variable_set(:@invoice, invoice)
    b = ctx.instance_eval { binding }
    html_body = ERB.new(File.read(File.join(views_root, 'invoices/html_email.erb'))).result(b)
    text_body = ERB.new(File.read(File.join(views_root, 'invoices/text_email.erb'))).result(b)
    public_path = File.join(root, 'public')

    web_path  = "/pdfs/#{invoice.client.client_key}"
    local_dir = File.join(public_path, web_path)
    filename  = "#{invoice.client.client_prefix}-#{invoice.num}.pdf"
    pdf_path  = File.join(local_dir, filename)

    Mailer.invoice(invoice, html_body: html_body, text_body: text_body, pdf_path: pdf_path)
    puts "  Sent: #{invoice.client.client_prefix}-#{invoice.num} to #{invoice.client.email}"
    invoice.update(sent_at: Time.now) if invoice.sent_at.nil?
  end
end

puts "Done: #{Time.now.strftime("%m/%d/%Y %H:%M:%S")}"
```

- [ ] **Step 5: Update `README.md`**

Replace with:

```markdown
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
```

- [ ] **Step 6: Final commit**

```bash
git add Procfile scripts/send_approve_invoices.rb README.md
git commit -m "feat: complete modernization — cleanup, scripts, Procfile, README"
```

---

## Verification

After all tasks are complete, verify the app boots and works end-to-end:

```bash
# 1. Build CSS
./tailwindcss -i public/css/input.css -o public/css/tailwind.css

# 2. Boot the app
RACK_ENV=development bundle exec puma -p 9393 -R config.ru

# 3. Visit http://localhost:9393
# Expected: redirect to /login

# 4. Create an admin user if you haven't already
bundle exec ruby db/seeds.rb

# 5. Login at http://localhost:9393/login
# Expected: dashboard loads with Tailwind styles

# 6. Create a client at /clients/create
# 7. Create an invoice for that client
# 8. Approve the invoice at /invoices/view/:id
# 9. Verify PDF downloads from the view page
# 10. Verify Send button is greyed out (SMTP not configured in .env)
```
