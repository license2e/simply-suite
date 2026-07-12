require 'dotenv'
Dotenv.load

$:.unshift File.expand_path('lib', __dir__)
$:.unshift File.expand_path('config', __dir__)
$:.unshift File.expand_path('app', __dir__)

require 'store'
require 'sinatra/base'
require 'base'

map '/clients'    do require 'clients';    run Clients    end
map '/invoices'   do require 'invoices';   run Invoices   end
map '/timesheets' do require 'timesheets'; run Timesheets end
map '/businesses' do require 'businesses'; run Businesses  end
map '/'           do require 'dashboard';  run Dashboard  end
