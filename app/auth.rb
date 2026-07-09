class Auth < SimplyBase
  set :layout_default, :'admin/layout-login'

  get '/' do
    if authorized?
      flash[:success] = "You are already logged in"
      redirect '/'
    end
    if inactivity?
      flash.now[:error] = "You were logged out due to inactivity"
    end
    @action_url = url("/?r=#{params[:r]}")
    @submit_value = 'Login'
    @page_title = 'Login'
    v :'auth/login'
  end

  get '/logout' do
    logout!
    flash[:success] = "You were successfully logged out!"
    redirect url('/')
  end

  post '/' do
    if params[:login][:login].empty? || params[:login][:password].empty?
      flash.now[:error] = "Please fill in all required fields"
      @action_url = url("/?r=#{params[:r]}")
      @submit_value = 'Login'
      @page_title = 'Login'
      v :'auth/login'
    elsif authenticate(params[:login][:login], params[:login][:password])
      redirect params[:r] unless params[:r].nil? || params[:r].empty?
      redirect '/'
    else
      flash.now[:error] = "Username or password was incorrect"
      @action_url = url("/?r=#{params[:r]}")
      @submit_value = 'Login'
      @page_title = 'Login'
      v :'auth/login'
    end
  end
end
