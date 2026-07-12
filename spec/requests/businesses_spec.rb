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

  it 'shows onboarding when there are no businesses' do
    get '/businesses'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to match(/Create.*business/i)
  end

  it 'renders the onboarding form as real HTML, not escaped text' do
    # Regression: `escape_html: true` made `<%= erb :partial %>` escape the
    # partial's HTML into visible text. The nested render must use `<%==`.
    get '/businesses'
    expect(last_response.body).to include('<form method="post" action="/businesses"')
    expect(last_response.body).to include('name="business[name]"')
    expect(last_response.body).not_to include('&lt;form')
  end

  it 'creates a business and selects it' do
    post '/businesses', business: { name: 'Acme Consulting', contact: 'Me', email: 'a@x.com',
                                    street: '1 Main', city: 'CLT', state: 'NC', zip: '28203' }
    expect(last_response.status).to eq(302)
    follow_redirect!
    expect(Store::Business.all.map(&:slug)).to include('acme-consulting')
    # session now has the business -> dashboard renders
    get '/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Acme Consulting')
  end

  it 'streams the active business logo and 404s when absent' do
    post '/businesses', business: { name: 'Logoed', contact: 'M', email: 'l@x.com',
                                    street: '1', city: 'CLT', state: 'NC', zip: '28203' }
    get '/businesses/logo'                # no logo uploaded yet
    expect(last_response.status).to eq(404)

    Store::Business.find('logoed').save_logo(File.expand_path('../../docs/invoice-screenshot.png', __dir__))
    get '/businesses/logo'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('image')
  end
end
