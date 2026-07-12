class Clients < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { require_business! }

  get '/' do
    per_page = 25
    all = current_business.clients
    @page = [params[:page].to_i, 1].max
    @total_pages = [(all.size.to_f / per_page).ceil, 1].max
    @clients = all.slice((@page - 1) * per_page, per_page) || []
    @pagination_path = '/clients'
    @page_title = 'Clients'
    v :'clients/list'
  end

  get '/view/:client_key' do
    @client = current_business.find_client(params[:client_key])
    halt 404 unless @client
    @page_title = "Client: #{@client.name}"
    v :'clients/view'
  end

  # NOTE: literal `/create` routes MUST be declared before the parameterized
  # `post '/:client_key'` update route — Sinatra matches in definition order,
  # so otherwise POST /clients/create is swallowed by the update route.
  get '/create' do
    @client = nil
    @action_url = '/clients/create'
    @submit_value = 'Create'
    @page_title = 'New Client'
    v :'clients/create'
  end

  post '/create' do
    p = params[:client]
    if p[:name].to_s.strip.empty?
      flash.now[:error] = 'Name is required'
      @action_url = '/clients/create'; @submit_value = 'Create'; @page_title = 'New Client'
      @client = nil
      halt v(:'clients/create')
    end
    current_business.create_client(
      name: p[:name], prefix: p[:client_prefix], contact: p[:contact], email: p[:email],
      street: p[:street], street2: p[:street2], city: p[:city], state: p[:state], zip: p[:zip]
    )
    flash[:success] = 'Client created successfully'
    redirect '/clients'
  end

  get '/edit/:client_key' do
    @client = current_business.find_client(params[:client_key])
    halt 404 unless @client
    @action_url = "/clients/#{@client.slug}"
    @submit_value = 'Update'
    @page_title = "Edit #{@client.name}"
    v :'clients/edit'
  end

  post '/:client_key' do
    client = current_business.find_client(params[:client_key])
    halt 404 unless client
    p = params[:client]
    client.update(
      prefix: p[:client_prefix], name: p[:name], contact: p[:contact], email: p[:email],
      street: p[:street], street2: p[:street2], city: p[:city], state: p[:state], zip: p[:zip],
      timesheet_period: (p[:timesheet_period].to_s.empty? ? nil : p[:timesheet_period]),
      default_rate: p[:default_rate]
    )
    flash[:success] = 'Client updated successfully'
    redirect '/clients'
  end

  get '/delete/:client_key' do
    client = current_business.find_client(params[:client_key])
    halt 404 unless client
    client.soft_delete
    flash[:success] = "#{client.name} and all their invoices have been deleted."
    redirect '/clients'
  end
end
