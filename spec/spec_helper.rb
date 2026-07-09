ENV['RACK_ENV'] = 'test'
ENV['DATABASE_URL'] = 'sqlite://./db/test.sqlite3'
ENV['SESSION_SECRET'] = 'test-secret-for-specs'

require 'dotenv'
# Don't load .env in test — use ENV vars above

require 'sequel'
DB = Sequel.connect(ENV['DATABASE_URL'])
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path('../db/migrations', __dir__))

$:.unshift File.expand_path('../lib', __dir__)
$:.unshift File.expand_path('../app', __dir__)

require 'sinatra/base'
require 'session_auth'
require 'mailer'
require 'base'
require_relative '../models/user'
require_relative '../models/models'
require_relative '../app/admin'
require_relative '../app/auth'
require_relative '../app/clients'
require_relative '../app/invoices'

require 'rspec'
require 'rack/test'
require 'bcrypt'

RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.before(:each) do
    DB[:services].delete
    DB[:invoices].delete
    DB[:clients].delete
    DB[:users].delete
  end
end

# Helper to create a test admin user and log in via the Auth app
module SpecHelpers
  def create_admin(login: 'admin@test.com', password: 'password123')
    User.create(
      login: login,
      hashed_password: BCrypt::Password.create(password).to_s,
      first_name: 'Test',
      last_name: 'Admin',
      is_admin: true,
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def login_as(login: 'admin@test.com', password: 'password123')
    post '/', { 'login[login]' => login, 'login[password]' => password }
  end

  def create_test_client
    client = Client.new
    client.title = 'Test Corp'
    client.client_prefix = 'TST'
    client.contact = 'John Doe'
    client.email = 'john@testcorp.com'
    client.street = '123 Test St'
    client.city = 'Charlotte'
    client.state = 'NC'
    client.zip = '28202'
    client.save
    client
  end

  def create_test_invoice(client)
    invoice = Invoice.create(
      client: client,
      num: '001',
      invoice_date: Time.now,
      total_amount: 1500.00,
      total_discount: 0.0,
      amount_paid: 0.0,
      terms: 'Payable upon receipt',
      notes: 'Thank you!',
      is_complete: true,
      created_at: Time.now,
      updated_at: Time.now
    )
    Service.create(
      invoice: invoice,
      item: 'Web Design',
      desc: 'Full redesign',
      qty: 1,
      cost: 1500.00,
      created_at: Time.now,
      updated_at: Time.now
    )
    invoice
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
end
