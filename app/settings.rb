require 'fileutils'

class Settings < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { require_business! }

  get '/' do
    @business = current_business
    logo = @business.resolve_logo
    @logo_url = logo ? logo[:web] : nil
    @page_title = 'Settings'
    v :'settings/index'
  end

  post '/company' do
    p = params[:company]
    current_business.update(
      name: p[:name], contact: p[:contact], email: p[:email],
      street: p[:street], city: p[:city], state: p[:state], zip: p[:zip],
      defaults: { timesheet_period: p[:timesheet_period], terms: p[:terms], notes: p[:notes] }
    )
    flash[:success] = 'Company info saved.'
    redirect '/settings'
  end

  post '/logo' do
    upload = params[:logo]
    unless upload && upload[:filename] && !upload[:filename].empty?
      flash[:error] = 'Please select an image file.'
      redirect '/settings'
    end
    unless upload[:type].to_s.start_with?('image/')
      flash[:error] = 'Please upload a valid image file.'
      redirect '/settings'
    end
    current_business.save_logo(upload[:tempfile].path)
    flash[:success] = 'Logo updated.'
    redirect '/settings'
  end
end
