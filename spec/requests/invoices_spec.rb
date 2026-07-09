require 'spec_helper'

RSpec.describe 'Invoices' do
  let(:combined_app) do
    Rack::Builder.new do
      map('/login') { run Auth }
      map('/invoices') { run Invoices }
    end
  end

  def app = combined_app

  def login!
    create_admin
    post '/login/', { 'login[login]' => 'admin@test.com', 'login[password]' => 'password123' }
  end

  before { login! }

  describe 'GET /invoices/:client_key' do
    it 'lists invoices for a client' do
      client = create_test_client
      get "/invoices/#{client.client_key}"
      expect(last_response.status).to eq(200)
    end
  end

  describe 'GET /invoices/view/:id' do
    it 'shows invoice detail' do
      client = create_test_client
      invoice = create_test_invoice(client)
      get "/invoices/view/#{invoice.id}"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('001')
    end

    it 'shows disabled Send button when SMTP not configured' do
      ENV['SMTP_HOST'] = ''
      client = create_test_client
      invoice = create_test_invoice(client)
      invoice.update(approved_on: Time.now)  # Send button only appears after approval
      get "/invoices/view/#{invoice.id}"
      expect(last_response.body).to include('SMTP not configured')
    end
  end

  describe 'GET /invoices/approve/:id' do
    it 'approves an invoice' do
      client = create_test_client
      invoice = create_test_invoice(client)
      expect(invoice.approved_on).to be_nil
      get "/invoices/approve/#{invoice.id}"
      expect(last_response.status).to eq(302)
      expect(Invoice[invoice.id].approved_on).not_to be_nil
    end
  end

  describe 'GET /invoices/paid/:id' do
    it 'marks invoice as paid' do
      client = create_test_client
      invoice = create_test_invoice(client)
      get "/invoices/paid/#{invoice.id}"
      expect(last_response.status).to eq(302)
      expect(Invoice[invoice.id].paid_at).not_to be_nil
    end
  end
end
