require 'json'
require 'sinatra/content_for'
require 'sinatra/flash'
require 'session_auth'

STATUS_COLORS = {
  'paid'     => 'bg-green-100 text-green-800',
  'late'     => 'bg-red-100 text-red-800',
  'sent'     => 'bg-blue-100 text-blue-800',
  'approved' => 'bg-yellow-100 text-yellow-800',
  'draft'    => 'bg-gray-100 text-gray-700'
}.freeze

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
  set :erb, escape_html: true
  set :layout_default, :'admin/layout-default'

  use Rack::Static, urls: ['/css', '/js', '/pdfs', '/client-assets', '/favicon.ico', '/favicon.gif'], root: 'public'

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

  # Resolves the logo, checking client-assets/ override before the default.
  # Returns { local: '/abs/path/to/logo.png', web: '/web/path/logo.png?v=...' }
  # or nil if no logo exists anywhere.
  def resolve_logo(public_path = settings.public_folder)
    override = File.join(public_path, 'client-assets', 'logo.png')
    if File.exist?(override)
      return { local: override, web: "/client-assets/logo.png?v=#{File.mtime(override).to_i}" }
    end
    default = File.join(public_path, 'css', 'images', 'logo.png')
    if File.exist?(default)
      return { local: default, web: "/css/images/logo.png?v=#{File.mtime(default).to_i}" }
    end
    nil
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
