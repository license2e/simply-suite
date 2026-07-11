require 'json'
require 'sinatra/content_for'
require 'sinatra/flash'

STATUS_COLORS = {
  'paid'     => 'bg-green-100 text-green-800',
  'late'     => 'bg-red-100 text-red-800',
  'sent'     => 'bg-blue-100 text-blue-800',
  'approved' => 'bg-yellow-100 text-yellow-800',
  'draft'    => 'bg-gray-100 text-gray-700'
}.freeze

class SimplyBase < Sinatra::Base
  helpers Sinatra::ContentFor
  register Sinatra::Flash

  set :views,          File.join(File.dirname(File.dirname(__FILE__)), 'views')
  set :public_folder,  File.join(File.dirname(File.dirname(__FILE__)), 'public')
  set :run,            false
  set :environment,    ENV.fetch('RACK_ENV', 'development').to_sym
  set :layout,         true
  set :logging,        true
  set :sessions,       true
  set :session_secret, ENV.fetch('SESSION_SECRET', SecureRandom.hex(64))
  set :erb, escape_html: true
  set :layout_default, :'admin/layout-default'

  use Rack::Static, urls: ['/css', '/js', '/favicon.ico', '/favicon.gif'], root: 'public'

  before do
    headers 'Content-Type' => 'text/html; charset=utf-8'
  end

  configure :development do
    set :reload_templates, true
  end

  def current_business
    slug = session[:business]
    @current_business ||= slug ? Store::Business.find(slug) : nil
  end

  def require_business!
    redirect '/businesses' unless current_business
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
