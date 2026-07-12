# spec/requests/businesses_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Businesses', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end
  around { |ex| with_temp_data_root { ex.run } }

  def make_business(name: 'Biz', **over)
    Store::Business.create({ name: name, contact: 'C', email: 'b@x.com',
                             street: '1', city: 'CLT', state: 'NC', zip: '28203' }.merge(over))
  end

  it 'redirects an empty business list to the new-business form (onboarding)' do
    get '/businesses'
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include('/businesses/new')
    follow_redirect!
    expect(last_response.status).to eq(200)
    expect(last_response.body).to match(/create your first business|welcome/i)
    expect(last_response.body).to include('name="business[name]"')
  end

  it 'lists businesses with a New button and per-row Edit + Open links' do
    make_business(name: 'Alpha Co')
    make_business(name: 'Beta Co')
    get '/businesses'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('New business')
    expect(last_response.body).to include('/businesses/alpha-co/edit')
    expect(last_response.body).to include('/businesses/beta-co/edit')
    expect(last_response.body).to include('/businesses/alpha-co/select')
  end

  it 'loads Stimulus from the local vendored file, with no CDN import' do
    get '/businesses/new'
    expect(last_response.body).to include("from '/js/stimulus.js'")
    expect(last_response.body).not_to include('cdn.jsdelivr')
  end

  it 'renders the new-business form as real HTML' do
    get '/businesses/new'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('<form')
    expect(last_response.body).to include('name="business[name]"')
    expect(last_response.body).to include('name="business[timesheet_period]"')
    expect(last_response.body).not_to include('&lt;form')
  end

  it 'creates a business with defaults and selects it' do
    post '/businesses', business: { name: 'Acme Consulting', contact: 'Me', email: 'a@x.com',
                                    street: '1 Main', city: 'CLT', state: 'NC', zip: '28203',
                                    timesheet_period: 'weekly', terms: 'Net 15', notes: 'ty' }
    expect(last_response.status).to eq(302)
    biz = Store::Business.find('acme-consulting')
    expect(biz).not_to be_nil
    expect(biz.defaults[:timesheet_period]).to eq('weekly')
    expect(biz.defaults[:terms]).to eq('Net 15')
    # session now has it -> dashboard renders
    get '/'
    expect(last_response.body).to include('Acme Consulting')
  end

  it 'edits a business: form pre-filled, update persists fields + defaults, slug unchanged, no duplicate' do
    b = make_business(name: 'Widgets Inc')
    get "/businesses/#{b.slug}/edit"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('value="Widgets Inc"')

    post "/businesses/#{b.slug}", business: { name: 'Widgets LLC', contact: 'C', email: 'b@x.com',
                                              street: '1', city: 'CLT', state: 'NC', zip: '28203',
                                              timesheet_period: 'quarterly', terms: 'Net 30', notes: 'thx' }
    expect(last_response.status).to eq(302)
    reloaded = Store::Business.find('widgets-inc')   # slug unchanged
    expect(reloaded.name).to eq('Widgets LLC')
    expect(reloaded.defaults[:timesheet_period]).to eq('quarterly')
    expect(Store::Business.all.size).to eq(1)        # updated in place, not duplicated
  end

  it 'streams a specific business logo via /:slug/logo (edit preview)' do
    b = make_business(name: 'Logoed')
    get "/businesses/#{b.slug}/logo"
    expect(last_response.status).to eq(404)          # no logo yet
    Store::Business.find('logoed').save_logo(File.expand_path('../../docs/invoice-screenshot.png', __dir__))
    get "/businesses/#{b.slug}/logo"
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('image')
  end

  it 'streams the active business logo and 404s when absent' do
    b = make_business(name: 'Active Co')
    post "/businesses/#{b.slug}/select"
    get '/businesses/logo'
    expect(last_response.status).to eq(404)
    Store::Business.find('active-co').save_logo(File.expand_path('../../docs/invoice-screenshot.png', __dir__))
    get '/businesses/logo'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('image')
  end

  it 'flashes an error and still creates the business when the logo is not an image' do
    non_image = Rack::Test::UploadedFile.new(File.expand_path('../../README.md', __dir__), 'text/plain')
    post '/businesses',
         business: { name: 'NoLogo Co', contact: 'M', email: 'n@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203' },
         logo: non_image
    expect(last_response.status).to eq(302)
    follow_redirect!
    expect(last_response.body).to match(/must be an image/i)
    biz = Store::Business.find('nologo-co')
    expect(biz).not_to be_nil
    expect(biz.logo_file).to be_nil
  end
end
