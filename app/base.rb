require 'json'
require 'haml'
require 'data_mapper'
#require 'sinatra/contrib'
require 'sinatra/content_for2'
require 'sinatra/head'
require 'sinatra/flash'
require 'sinatra/sessionauth'
require 'action_mailer'

class SimplyBase < Sinatra::Base
                                 
  # Register Extensions and Helpers
  helpers Sinatra::SessionAuth::Helpers
  helpers Sinatra::ContentFor2
  #register Sinatra::RespondWith
  register Sinatra::Head
  register Sinatra::Flash
  
  # Settings
  set :app_id, "emg-panel"
  set :cmp_env, {:dev => "development", :prod => "production"}
  # ---------
  set :views, File.join(File.dirname(File.dirname(__FILE__)),'views')
  set :public_path, File.join(File.dirname(File.dirname(__FILE__)), 'public')
  set :run, false
  set :env, ENV["RACK_ENV"]
  set :haml, :format => :html5
  set :layout, true
  set :logging, true
  set :sessions, true
  set :session_secret, "lkA$d24y1sEf-!@^a5et3-T!@^A4t634ta}"
  set :layout_default, :'layout'  
  set :stylesheet_path, '/css'
  set :javascript_path, '/js'
  
  
  # set Rack
  use Rack::Static, :urls => [settings.stylesheet_path, settings.javascript_path, '/pdfs'], :root => 'public'
  
  # set the default stylesheets and javascripts
  stylesheets << "fonts.css"
  stylesheets << "css-reset.css"
  stylesheets << "colors.css"
  stylesheets << "style.css"
  javascripts << "jquery-1.7.1.min.js"
  
  # set utf-8 for outgoing
  before do
    headers "Content-Type" => "text/html; charset=utf-8"
  end

  configure do
    DataMapper::Logger.new('logs/datamapper-debug.log', :debug)
    require 'app/configure'
  end
  
  configure :development do
    set :reload_templates, true
    # create, upgrade, or migrate tables automatically
    DataMapper::Model.raise_on_save_failure = true
    DataMapper.auto_upgrade!
  end
  
  def login_url_redirect
    return '/login'
  end

  def set_user_data(u)
    session[:auth_user][:id] = u.id
    session[:auth_user][:is_admin] = u.is_admin    
  end
  
  def env_override(type, truth, falsehood)
    return (settings.cmp_env[type] == settings.env) ? truth : falsehood
  end

  def access_role?(role)
    key = :"is_#{role}"
    if session[:auth_user].has_key?(key) && session[:auth_user][key] == true then
      return true
    end
    return false
  end
  
  def v(template, options={}) 
    if !options[:layout] then
      options = options.merge(:layout => settings.layout_default)
    end
    if request.xhr? then 
      options[:layout] = false
    end
    haml(template, options) 
  end
  
  not_found do
    title << "Not Found"
    v :"admin/not_found", :layout => :'admin/layout'
  end
  
  error do
    title << "Error"
    v :"admin/error", :layout => :'admin/layout'
  end
  
end
