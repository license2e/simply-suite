require 'fileutils'

class Settings < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { authorize! }

  LOGO_UPLOAD_PATH = 'client-assets/logo.png'.freeze

  get '/' do
    @company = Company.first || Company.new
    logo = resolve_logo
    @logo_url = logo ? logo[:web] : nil
    @page_title = 'Settings'
    v :'settings/index'
  end

  post '/company' do
    p = params[:company]
    attrs = {
      name:    p[:name],
      contact: p[:contact],
      email:   p[:email],
      street:  p[:street],
      city:    p[:city],
      state:   p[:state],
      zip:     p[:zip]
    }
    if (company = Company.first)
      company.update(attrs)
    else
      Company.create(attrs)
    end
    flash[:success] = "Company info saved."
    redirect url('/')
  end

  post '/logo' do
    upload = params[:logo]
    unless upload && upload[:filename] && !upload[:filename].empty?
      flash[:error] = "Please select an image file."
      redirect url('/')
    end
    unless upload[:type].to_s.start_with?('image/')
      flash[:error] = "Please upload a valid image file."
      redirect url('/')
    end
    dest = File.join(settings.public_folder, LOGO_UPLOAD_PATH)
    FileUtils.cp(upload[:tempfile].path, dest)
    flash[:success] = "Logo updated."
    redirect url('/')
  end
end
