class Admin < SimplyBase
  set :layout_default, :'admin/layout-default'

  get '/?' do
    authorize!
    @page_title = 'Dashboard'
    v :'admin/home'
  end
end
