class Clients < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { authorize! }

  get '/' do
    per_page = 25
    @page = [params[:page].to_i, 1].max
    @total_pages = (Client.count.to_f / per_page).ceil
    @clients = Client.order(:name).limit(per_page).offset((@page - 1) * per_page).all
    @pagination_path = '/clients'
    @page_title = 'Clients'
    v :'clients/list'
  end

  get '/view/:client_key' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    @page_title = "Client: #{@client.name}"
    v :'clients/view'
  end

  get '/edit/:client_key' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    @action_url = url("/update/#{@client.id}")
    @submit_value = 'Update'
    @page_title = "Edit #{@client.name}"
    v :'clients/edit'
  end

  post '/update/:id' do
    client = Client[params[:id].to_i]
    halt 404 unless client
    p = params[:client]
    begin
      client.update(
        client_prefix: p[:client_prefix],
        name:          p[:name],
        contact:       p[:contact],
        email:         p[:email],
        street:        p[:street],
        street2:       p[:street2],
        city:          p[:city],
        state:         p[:state],
        zip:           p[:zip]
      )
      flash[:success] = "Client updated successfully"
    rescue Sequel::ValidationFailed => e
      flash[:error] = e.message
    end
    redirect url('/')
  end

  get '/create' do
    @client = Client.new
    @action_url = url('/create')
    @submit_value = 'Create'
    @page_title = 'New Client'
    v :'clients/create'
  end

  post '/create' do
    p = params[:client]
    @client = Client.new
    @client.title = p[:name]
    @client.client_prefix = p[:client_prefix]
    @client.contact  = p[:contact]
    @client.email    = p[:email]
    @client.street   = p[:street]
    @client.street2  = p[:street2]
    @client.city     = p[:city]
    @client.state    = p[:state]
    @client.zip      = p[:zip]
    begin
      @client.save
      flash[:success] = "Client created successfully"
      redirect url('/')
    rescue Sequel::ValidationFailed => e
      flash.now[:error] = e.message
      @action_url = url('/create')
      @submit_value = 'Create'
      @page_title = 'New Client'
      v :'clients/create'
    end
  end
end
