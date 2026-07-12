class Businesses < SimplyBase
  set :layout_default, :'admin/layout-default'

  get '/?' do
    @businesses = Store::Business.all
    @page_title = @businesses.empty? ? 'Welcome' : 'Choose a business'
    v :'businesses/index'
  end

  post '/?' do
    p = params[:business] || {}
    if p[:name].to_s.strip.empty?
      flash[:error] = 'Business name is required.'
      redirect '/businesses'
    end
    logo_src = nil
    upload = params[:logo]
    if upload && upload[:tempfile] && upload[:type].to_s.start_with?('image/')
      logo_src = upload[:tempfile].path
    end
    biz = Store::Business.create(
      { name: p[:name], contact: p[:contact], email: p[:email],
        street: p[:street], city: p[:city], state: p[:state], zip: p[:zip] },
      logo_src
    )
    session[:business] = biz.slug
    flash[:success] = "#{biz.name} created."
    redirect '/'
  end

  post '/:slug/select' do
    biz = Store::Business.find(params[:slug])
    halt 404 unless biz
    session[:business] = biz.slug
    redirect '/'
  end

  get '/logo' do
    biz = current_business
    halt 404 unless biz && biz.logo_file
    send_file biz.logo_file, type: 'image/png', disposition: 'inline'
  end
end
