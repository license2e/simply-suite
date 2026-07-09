require 'spec_helper'

RSpec.describe 'Clients' do
  # Build a combined rack app that shares sessions between Auth and Clients
  let(:combined_app) do
    Rack::Builder.new do
      map('/login') { run Auth }
      map('/clients') { run Clients }
    end
  end

  def app = combined_app

  def login!
    create_admin
    post '/login/', { 'login[login]' => 'admin@test.com', 'login[password]' => 'password123' }
  end

  before { login! }

  describe 'GET /clients/' do
    it 'returns 200' do
      get '/clients/'
      expect(last_response.status).to eq(200)
    end

    it 'shows existing clients' do
      create_test_client
      get '/clients/'
      expect(last_response.body).to include('Test Corp')
    end
  end

  describe 'POST /clients/create' do
    it 'creates a client and redirects' do
      expect {
        post '/clients/create', {
          'client[name]' => 'New Co',
          'client[client_prefix]' => 'NEW',
          'client[contact]' => 'Jane',
          'client[email]' => 'jane@newco.com',
          'client[street]' => '1 Main St',
          'client[city]' => 'Charlotte',
          'client[state]' => 'NC',
          'client[zip]' => '28202'
        }
      }.to change { Client.count }.by(1)
      expect(last_response.status).to eq(302)
    end
  end
end
