#!/usr/bin/env ruby
# Generates a sample invoice PDF for README documentation.
# Usage: bundle exec ruby scripts/generate_invoice_pdf.rb

require 'fileutils'
require 'dotenv'
Dotenv.load

ENV['DATABASE_URL'] = 'sqlite://./db/screenshot.sqlite3'
ENV['SESSION_SECRET'] = 'pdf-script-session-secret-must-be-at-least-64-characters-long-padding'
ENV['RACK_ENV'] = 'development'

require 'sequel'
DB = Sequel.connect(ENV['DATABASE_URL'])
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path('../db/migrations', __dir__))

DB[:services].delete
DB[:invoices].delete
DB[:clients].delete
DB[:users].delete

$:.unshift File.expand_path('../lib', __dir__)
$:.unshift File.expand_path('../app', __dir__)

require 'bcrypt'
require_relative '../models/user'
require_relative '../models/models'

client = Client.new
client.title         = 'Acme Corporation'
client.client_prefix = 'ACM'
client.contact       = 'Jane Smith'
client.email         = 'jane@acmecorp.com'
client.street        = '1800 Camden Rd, Suite 200'
client.city          = 'Charlotte'
client.state         = 'NC'
client.zip           = '28203'
client.save

invoice = Invoice.create(
  client:         client,
  num:            '007',
  invoice_date:   Time.now,
  total_amount:   4750.00,
  total_discount: 0.0,
  amount_paid:    0.0,
  terms:          'Net 30 days',
  notes:          'Thank you for choosing Simply Suite. We appreciate your business.',
  is_complete:    true,
  approved_on:    Time.now,
  created_at:     Time.now,
  updated_at:     Time.now
)

Service.create(invoice: invoice, item: 'Strategy',    desc: 'Digital strategy & brand audit',   qty: 1,  cost: 1500.00, created_at: Time.now, updated_at: Time.now)
Service.create(invoice: invoice, item: 'Design',      desc: 'UI/UX design for 10 core screens', qty: 1,  cost: 2000.00, created_at: Time.now, updated_at: Time.now)
Service.create(invoice: invoice, item: 'Development', desc: 'Frontend development @ $125/hr',   qty: 10, cost: 125.00,  created_at: Time.now, updated_at: Time.now)

require 'sinatra/base'
require 'session_auth'
require 'mailer'
require 'base'
require_relative '../app/admin'
require_relative '../app/auth'
require_relative '../app/clients'
require_relative '../app/invoices'

public_path = File.expand_path('../public', __dir__)
pdf_web_path = Invoices.new!.send(:create_invoice_pdf, public_path, invoice, '/css/images/logo.png')

src  = File.join(public_path, pdf_web_path)
dest = File.expand_path('../docs/sample-invoice.pdf', __dir__)
FileUtils.mkdir_p(File.dirname(dest))
FileUtils.cp(src, dest)
puts "PDF saved to docs/sample-invoice.pdf"

File.delete('db/screenshot.sqlite3') if File.exist?('db/screenshot.sqlite3')
