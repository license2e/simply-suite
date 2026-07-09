require 'spec_helper'

RSpec.describe 'Auth' do
  def app = Auth

  describe 'GET /' do
    it 'renders the login form' do
      get '/'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('login[login]')
      expect(last_response.body).to include('login[password]')
    end
  end

  describe 'POST /' do
    before { create_admin }

    it 'redirects to / on valid credentials' do
      post '/', { 'login[login]' => 'admin@test.com', 'login[password]' => 'password123' }
      expect(last_response.status).to eq(302)
    end

    it 'renders the form again with error on invalid password' do
      post '/', { 'login[login]' => 'admin@test.com', 'login[password]' => 'wrong' }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('incorrect')
    end

    it 'renders form again when fields are empty' do
      post '/', { 'login[login]' => '', 'login[password]' => '' }
      expect(last_response.status).to eq(200)
    end
  end

  describe 'GET /logout' do
    it 'redirects to /' do
      get '/logout'
      expect(last_response.status).to eq(302)
    end
  end
end
