#$LOAD_PATH.unshift("./lib")

log = File.new("logs/stdlog-debug.log", "a")
STDOUT.reopen(log)
STDERR.reopen(log)

$:.unshift File.expand_path("../lib", __FILE__)
$:.unshift File.expand_path("../config", __FILE__)
$:.unshift File.expand_path("../app", __FILE__)

# Require this app's settings
require 'app_settings'

require 'sinatra/base'
require 'base'

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
