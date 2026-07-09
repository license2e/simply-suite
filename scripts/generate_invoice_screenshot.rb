#!/usr/bin/env ruby
# Generates a screenshot of the invoice view page for README documentation.
# Requirements: Chrome/Chromium installed, ferrum gem installed (bundle install)
# Usage: bundle exec ruby scripts/generate_invoice_screenshot.rb

require 'fileutils'
require 'dotenv'
Dotenv.load

# Use a dedicated screenshot database
ENV['DATABASE_URL'] = 'sqlite://./db/screenshot.sqlite3'
ENV['SESSION_SECRET'] = 'screenshot-session-secret-must-be-at-least-64-characters-long-padding'
ENV['RACK_ENV'] = 'development'

require 'sequel'
DB = Sequel.connect(ENV['DATABASE_URL'])
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path('../db/migrations', __dir__))

# Clean slate
DB[:services].delete
DB[:invoices].delete
DB[:clients].delete
DB[:users].delete

$:.unshift File.expand_path('../lib', __dir__)
$:.unshift File.expand_path('../app', __dir__)

require 'bcrypt'
require_relative '../models/user'
require_relative '../models/models'

# Seed sample data
admin = User.create(
  login: 'demo@simplysuite.com',
  hashed_password: BCrypt::Password.create('demo1234').to_s,
  first_name: 'Demo', last_name: 'Admin', is_admin: true,
  created_at: Time.now, updated_at: Time.now
)

client = Client.new
client.title = 'Acme Corporation'
client.client_prefix = 'ACM'
client.contact = 'Jane Smith'
client.email = 'jane@acmecorp.com'
client.street = '1800 Camden Rd, Suite 200'
client.city = 'Charlotte'
client.state = 'NC'
client.zip = '28203'
client.save

invoice = Invoice.create(
  client: client,
  num: '007',
  invoice_date: Time.now,
  total_amount: 4750.00,
  total_discount: 0.0,
  amount_paid: 0.0,
  terms: 'Net 30 days',
  notes: 'Thank you for choosing Simply Suite. We appreciate your business.',
  is_complete: true,
  approved_on: Time.now,
  created_at: Time.now,
  updated_at: Time.now
)

Service.create(invoice: invoice, item: 'Strategy',    desc: 'Digital strategy & brand audit',         qty: 1,  cost: 1500.00, created_at: Time.now, updated_at: Time.now)
Service.create(invoice: invoice, item: 'Design',      desc: 'UI/UX design for 10 core screens',       qty: 1,  cost: 2000.00, created_at: Time.now, updated_at: Time.now)
Service.create(invoice: invoice, item: 'Development', desc: 'Frontend development @ $125/hr',         qty: 10, cost: 125.00,  created_at: Time.now, updated_at: Time.now)

# Build the Rack app
require 'sinatra/base'
require 'session_auth'
require 'mailer'
require 'base'
require_relative '../app/admin'
require_relative '../app/auth'
require_relative '../app/clients'
require_relative '../app/invoices'

require 'rack'
require 'mail'

app = Rack::Builder.new do
  map('/') { run Admin }
  map('/login') { run Auth }
  map('/clients') { run Clients }
  map('/invoices') { run Invoices }
end.to_app

# Start Puma in a background thread
PORT = 9394
require 'puma'
require 'puma/configuration'
require 'puma/launcher'

server_thread = Thread.new do
  config = Puma::Configuration.new do |c|
    c.bind "tcp://127.0.0.1:#{PORT}"
    c.app app
    c.quiet
  end
  Puma::Launcher.new(config).run
end

# Wait for server to be ready
require 'net/http'
print 'Waiting for server'
30.times do
  begin
    Net::HTTP.get(URI("http://127.0.0.1:#{PORT}/login"))
    break
  rescue
    print '.'
    sleep 0.5
  end
end
puts ' ready!'

# Use Ferrum for screenshot
require 'ferrum'

browser = Ferrum::Browser.new(
  headless: true,
  window_size: [1280, 900],
  browser_options: { 'no-sandbox': nil }
)

begin
  # Log in via JavaScript (brackets in name attr confuse CSS selector engines)
  browser.goto("http://127.0.0.1:#{PORT}/login")
  sleep 1
  puts "Page title: #{browser.evaluate('document.title')}"
  puts "Body snippet: #{browser.evaluate('document.body.innerHTML.substring(0, 300)')}"
  browser.execute(<<~JS)
    document.querySelector('input[type="text"]').value = 'demo@simplysuite.com';
    document.querySelector('input[type="password"]').value = 'demo1234';
    document.querySelector('button[type="submit"]').click();
  JS
  sleep 1

  # Navigate to invoice view
  browser.goto("http://127.0.0.1:#{PORT}/invoices/view/#{invoice.id}")
  sleep 1.5

  # Take screenshot
  FileUtils.mkdir_p('docs')
  browser.screenshot(path: 'docs/invoice-screenshot.png', full: false)
  puts "Screenshot saved to docs/invoice-screenshot.png"
ensure
  browser.quit
  server_thread.kill
end

# Clean up screenshot DB
File.delete('db/screenshot.sqlite3') if File.exist?('db/screenshot.sqlite3')
