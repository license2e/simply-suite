class Admin < SimplyBase
  set :layout_default, :'admin/layout-default'
  title << 'Admin'
  
  configure do
    require './models/user'
    DataMapper.finalize
  end
    
  get '/?' do
    authorize!
    title << 'Home'
    v :"admin/home"
  end
  
  get '/login' do
    title << 'Login'
    v :"admin/login"
  end
  
  get '/upgrade-db/?' do 
    if !access_role?("admin") then
      redirect '/admin/'
    end
    
    BillingCode.auto_migrate! # unless BillingCode.storage_exists?
    
    DataMapper.auto_upgrade!
    DataMapper.finalize
    redirect '/admin/'
  end
  
end