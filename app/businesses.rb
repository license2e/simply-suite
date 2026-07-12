class Businesses < SimplyBase
  set :layout_default, :'admin/layout-default'

  helpers do
    # Build the attrs hash for Business.create/#update from the form params.
    # Defaults are compacted so a caller that omits period/terms/notes doesn't
    # clobber the stored defaults with nil.
    def business_params(p)
      { name: p[:name], contact: p[:contact], email: p[:email],
        street: p[:street], city: p[:city], state: p[:state], zip: p[:zip],
        defaults: { timesheet_period: p[:timesheet_period], terms: p[:terms], notes: p[:notes] }.compact }
    end

    # Returns [logo_src_path_or_nil, rejected?]. rejected? is true only when a
    # non-image file was actually chosen.
    def logo_from_upload
      upload = params[:logo]
      return [nil, false] unless upload && upload[:tempfile] && !upload[:filename].to_s.empty?
      upload[:type].to_s.start_with?('image/') ? [upload[:tempfile].path, false] : [nil, true]
    end
  end

  get '/?' do
    @businesses = Store::Business.all
    redirect '/businesses/new' if @businesses.empty?
    @page_title = 'Choose a business'
    v :'businesses/index'
  end

  get '/new' do
    @business = nil
    @first_business = Store::Business.all.empty?
    @action_url = '/businesses'
    @submit_value = 'Create business'
    @page_title = @first_business ? 'Welcome' : 'New business'
    v :'businesses/form'
  end

  post '/?' do
    p = params[:business] || {}
    if p[:name].to_s.strip.empty?
      flash[:error] = 'Business name is required.'
      redirect '/businesses/new'
    end
    logo_src, logo_rejected = logo_from_upload
    biz = Store::Business.create(business_params(p), logo_src)
    session[:business] = biz.slug
    flash[:success] = "#{biz.name} created."
    flash[:error] = 'Logo must be an image file — the business was created without a logo.' if logo_rejected
    redirect '/'
  end

  # Active business's logo (used by invoice preview + the switcher).
  get '/logo' do
    biz = current_business
    halt 404 unless biz && biz.logo_file
    send_file biz.logo_file, type: 'image/png', disposition: 'inline'
  end

  get '/:slug/edit' do
    @business = Store::Business.find(params[:slug])
    halt 404 unless @business
    @action_url = "/businesses/#{@business.slug}"
    @submit_value = 'Save changes'
    @page_title = "Edit #{@business.name}"
    v :'businesses/form'
  end

  # A specific business's logo (edit-form preview, correct even when it isn't active).
  get '/:slug/logo' do
    biz = Store::Business.find(params[:slug])
    halt 404 unless biz && biz.logo_file
    send_file biz.logo_file, type: 'image/png', disposition: 'inline'
  end

  post '/:slug/select' do
    biz = Store::Business.find(params[:slug])
    halt 404 unless biz
    session[:business] = biz.slug
    redirect '/'
  end

  post '/:slug' do
    biz = Store::Business.find(params[:slug])
    halt 404 unless biz
    p = params[:business] || {}
    if p[:name].to_s.strip.empty?
      flash[:error] = 'Business name is required.'
      redirect "/businesses/#{biz.slug}/edit"
    end
    biz.update(business_params(p))
    logo_src, logo_rejected = logo_from_upload
    biz.save_logo(logo_src) if logo_src
    flash[:success] = "#{biz.name} updated."
    flash[:error] = 'Logo must be an image file — kept the existing logo.' if logo_rejected
    redirect '/businesses'
  end
end
