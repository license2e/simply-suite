class Dashboard < SimplyBase
  before { require_business! }

  get '/?' do
    @page_title = 'Dashboard'
    v :'admin/home'
  end
end
