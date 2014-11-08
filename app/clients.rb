
class Clients < SimplyBase
  set :layout_default, :'admin/layout-default'
  title << 'Admin'
  stylesheets << 'clients.css'
  
  configure do
    require './models/user'
    require './models/models'
    DataMapper.finalize
  end
  
  before do
    authorize!
  end
  
  get '/' do
    @clients =  Client.all()
    
    title << "Clients"
    v :"clients/list"
  end
  
  get '/view/:client_key' do
    @client =  nil
    if params[:client_key] != nil then
      @client = Client.first(:client_key => params[:client_key])

      title << "Client details for: #{@client.name}"
      v :"clients/view"
    else
      redirect url('/')
    end
  end
  
  get '/edit/:client_key' do
    @client =  nil
    if params[:client_key] != nil then
      @client = Client.first(:client_key => params[:client_key])
     
      @action_url = url("/update/#{@client.id}")
      @submit_value = "Update"
      title << "Update details for: #{@client.name}"
      v :"clients/edit"
    else
      redirect url('/')
    end
  end
  
  post '/update/:id' do
    if params[:id] != nil then
      clientParams = params[:client]
      client = Client.get(params[:id])
      begin
        # update the invoice
        client.update({
          :client_prefix => clientParams[:client_prefix],
          :name => clientParams[:name],
          :contact => clientParams[:contact],
          :email => env_override(:dev, "testing+#{settings.app_id}@eonmediagroup.com", clientParams[:email]),
          :street => clientParams[:street],
          :street2 => clientParams[:street2],
          :city => clientParams[:city],
          :state => clientParams[:state],
          :zip => clientParams[:zip],
        })
        flash[:success] = "Successfully updated client details!"
      rescue DataMapper::SaveFailureError => e
        raise "#{e.to_s} -- validation(s): #{client.errors.values.join(', ')}"
      rescue StandardError => e
        raise "#{e.to_s}"
      end
    end
    redirect url('/')
  end
  
  get '/create' do
    @client = Client.new()
    @action_url = url("/create")
    @submit_value = "Create"
    title << "Create New Client"
    v :"clients/create"
  end
  
  post '/create' do
    clientParams = params[:client]
    client = Client.new({
      :title => clientParams[:name],
      :client_prefix => clientParams[:client_prefix],
      :contact => clientParams[:contact],
      :email => clientParams[:email],
      :street => clientParams[:street],
      :street2 => clientParams[:street2],
      :city => clientParams[:city],
      :state => clientParams[:state],
      :zip => clientParams[:zip]
    })
    if clientParams[:name].empty? || clientParams[:client_prefix].empty? || clientParams[:contact].empty? || clientParams[:email].empty? || clientParams[:street].empty? || clientParams[:city].empty? || clientParams[:state].empty? || clientParams[:zip].empty? then
      @client = client
      flash.now[:error] = "Please fill in all of the require fields"
      @action_url = url("/create")
      @submit_value = "Create"
      title << "Create New Client"
      v :"clients/create"
    else
      begin
        # update the invoice
        client.save
        flash[:success] = "Successfully updated client details!"
      rescue DataMapper::SaveFailureError => e
        raise "#{e.to_s} -- validation(s): #{client.errors.values.join(', ')}"
      rescue StandardError => e
        raise "#{e.to_s}"
      end
      redirect url('/')
    end
  end
  
  get '/dummy-client' do
    
    client = Client.new({
      :title => "Dap Inc.",
      :client_prefix => "DAP",
      :contact => "Ilya Shindyapin",
      :email => "ilya+test@shindyapin.com",
      :street => "123 Some Street",
      :street2 => "Suite 1423",
      :city => "Charlotte",
      :state => "NC",
      :zip => "28277"
    })
    client.save
    
    redirect url('/')
  end
  
end