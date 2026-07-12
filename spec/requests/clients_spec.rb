# spec/requests/clients_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Clients', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end

  around do |ex|
    with_temp_data_root do
      @biz = Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203')
      ex.run
    end
  end

  def select_business
    post "/businesses/#{@biz.slug}/select"
  end

  it 'creates, updates, lists and deletes a client' do
    select_business
    post '/clients/create', client: { name: 'Widgets Inc', client_prefix: 'WID', contact: 'J',
                                       email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203' }
    expect(@biz.find_client('widgets-inc')).not_to be_nil

    get '/clients'
    expect(last_response.body).to include('Widgets Inc')

    post '/clients/widgets-inc', client: { client_prefix: 'WID', name: 'Widgets LLC', contact: 'J',
                                           email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203' }
    expect(@biz.find_client('widgets-inc').name).to eq('Widgets LLC')

    get '/clients/delete/widgets-inc'
    expect(@biz.find_client('widgets-inc')).to be_nil
  end

  it 'redirects to /businesses without an active business' do
    get '/clients'
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include('/businesses')
  end

  it 'persists a per-client default rate from the edit form' do
    select_business
    @biz.create_client(name: 'Rate Co', prefix: 'RC', contact: 'x', email: 'r@x.com',
                       street: '1', street2: '', city: 'CLT', state: 'NC', zip: '28203')
    post '/clients/rate-co', client: { client_prefix: 'RC', name: 'Rate Co', contact: 'x', email: 'r@x.com',
                                       street: '1', street2: '', city: 'CLT', state: 'NC', zip: '28203',
                                       default_rate: '$150' }
    expect(@biz.find_client('rate-co').default_rate).to eq('150')
  end
end
