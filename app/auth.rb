
class Auth < SimplyBase
  set :layout_default, :'admin/layout-login'
  title << 'Login'
  javascripts << 'jquery.example.min.js'
  javascripts << 'login.js'
  
  get '/' do
    if authorized? then
      flash[:success] = "You are already logged in"
      redirect '/'
    end
    if inactivity? then
      flash.now[:error] = "You were logged out due to inactivity"
    end
    @action_url = url("/?r=#{params[:r]}")
    @submit_value = 'Login'
    v :"auth/login"
  end
  
  get '/logout' do
    logout!
    flash[:success] = "You were successfully logged out!"
    redirect url('/')
  end
  
  post '/' do
    if params[:login][:login] == "" || params[:login][:password] == "" then
      flash[:error] = "Please fill in all required data"
    elsif authenticate(User, params[:login][:login], params[:login][:password]) then
      redirect params[:r] unless params[:r].nil?
      redirect '/'
    else 
      flash[:error] = "Username or password was incorrect"
    end  
    redirect url('/')
  end

=begin
  get '/forgot' do
    v :"auth/forgot"
  end
  
  post '/forgot' do
    @user = User.first(:login => params[:forgot][:login])
    if !@user.nil? then
      
      email_options = {}
      email_options[:user] = @user
      email_options[:html_body] = haml :"auth/html_email_forgot"
      email_options[:text_body] = haml :"auth/text_email_forgot"
      
      class Mailman < ActionMailer::Base
        def forgot(options)
          @user = options[:user]
          html_body = options[:html_body]
          text_body = options[:text_body]
          mail(
            :to => "#{@user.login}",
            :from => "Admin - EON Media Group <admin@eonmediagroup.com>",
            :subject => "Forgot password for: #{@user.login}"
          ) do |format|  
            format.text { text_body.to_s }
            format.html { html_body }
          end
        end
      end
      Mailman.forgot(email_options).deliver
      redirect url('/login')
    else
      flash[:error] = "User login was not found, please try again."
      redirect url('/forgot')
    end
  end
=end
  
=begin
  get '/register' do
    title << 'Register'
    @action_url = url('/register')
    @submit_value = 'Register'
    v :"auth/register"
  end
  
  post '/register' do
    
    registrationData = params[:register]
    puts registrationData.inspect
    
    if registrationData[:password] != registrationData[:confirm_password] then
      flash[:error] = "The passwords do not match"
    else
      user = User.new({
        :login => registrationData[:login],
        :password => registrationData[:password],
        :first_name => registrationData[:first_name],
        :last_name => registrationData[:last_name],
      })
      # set the first registrant the admin
      admins = User.count(:is_admin => true)
      puts admins.inspect
      if admins == 0 then
        user.is_admin = true
      end
      # on save try logging in
      if user.save then
        flash[:success] = "Successfully registered!"
        redirect url('/')
      end
    end
    #redirect url('/register')
  end
=end
  
end