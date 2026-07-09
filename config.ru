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
