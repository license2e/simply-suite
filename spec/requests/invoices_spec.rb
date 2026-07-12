# spec/requests/invoices_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Invoices', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end

  around do |ex|
    with_temp_data_root do
      @biz = Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203')
      @client = @biz.create_client(name: 'Widgets Inc', prefix: 'WID', contact: 'J', email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203')
      ex.run
    end
  end

  before { post "/businesses/#{@biz.slug}/select" }

  def svc(i) { "invoice[services][#{i}][item]" => 'Dev', "invoice[services][#{i}][desc]" => 'x',
               "invoice[services][#{i}][service_date]" => '07/05/2026', "invoice[services][#{i}][qty]" => '2',
               "invoice[services][#{i}][cost]" => '125' } end

  it 'creates an invoice with an assigned number, a PDF, and serves it' do
    post '/invoices/widgets-inc/create', { 'invoice[num]' => '', 'invoice[invoice_date]' => '07/09/2026',
      'invoice[total_amount]' => '250', 'invoice[total_discount]' => '0', 'invoice[amount_paid]' => '0',
      'invoice[terms]' => 'Net 30', 'invoice[notes]' => 'thanks' }.merge(svc(0))
    inv = @client.invoices.first
    expect(inv.num).to eq('001')
    expect(inv.services.first.item).to eq('Dev')
    expect(inv.pdf_exists?).to be true

    get '/invoices/widgets-inc/001/pdf'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('application/pdf')
  end

  it '404s the pdf route when no PDF exists' do
    @client.create_invoice(services: []) # draft, no PDF
    get '/invoices/widgets-inc/001/pdf'
    expect(last_response.status).to eq(404)
  end

  it 'approves and marks paid' do
    @client.create_invoice(num: '001', services: [])
    get '/invoices/widgets-inc/001/approve'
    expect(@client.find_invoice('001').approved_on).not_to be_nil
    get '/invoices/widgets-inc/001/paid'
    expect(@client.find_invoice('001').get_status).to eq('paid')
  end

  it 'update replaces services and keeps the number even if a different num is submitted' do
    @client.create_invoice(num: '001', invoice_date: nil,
      services: [{ item: 'Old', desc: 'old desc', qty: 1, cost: 100 }])

    post '/invoices/widgets-inc/001', { 'invoice[num]' => '999', 'invoice[invoice_date]' => '07/09/2026',
      'invoice[total_amount]' => '250', 'invoice[total_discount]' => '0', 'invoice[amount_paid]' => '0',
      'invoice[terms]' => 'Net 30', 'invoice[notes]' => 'thanks',
      'invoice[services][0][item]' => 'New', 'invoice[services][0][desc]' => 'new desc',
      'invoice[services][0][service_date]' => '07/05/2026', 'invoice[services][0][qty]' => '3',
      'invoice[services][0][cost]' => '50' }.merge(svc(1))

    expect(@client.find_invoice('001')).not_to be_nil
    expect(@client.find_invoice('999')).to be_nil

    inv = @client.find_invoice('001')
    expect(inv.services.map(&:item)).to eq(%w[New Dev])
  end

  it 'drops blank service rows on save' do
    @client.create_invoice(num: '001', services: [])

    post '/invoices/widgets-inc/001', { 'invoice[num]' => '001', 'invoice[invoice_date]' => '07/09/2026',
      'invoice[total_amount]' => '250', 'invoice[total_discount]' => '0', 'invoice[amount_paid]' => '0',
      'invoice[terms]' => 'Net 30', 'invoice[notes]' => 'thanks',
      'invoice[services][0][item]' => '', 'invoice[services][0][desc]' => '',
      'invoice[services][0][service_date]' => '', 'invoice[services][0][qty]' => '',
      'invoice[services][0][cost]' => '' }.merge(svc(1))

    inv = @client.find_invoice('001')
    expect(inv.services.size).to eq(1)
    expect(inv.services.first.item).to eq('Dev')
  end

  it 'delete archives the invoice' do
    @client.create_invoice(num: '001', services: [])
    get '/invoices/widgets-inc/001/delete'
    expect(@client.find_invoice('001')).to be_nil
  end

  it 'mark_sent sets sent_at' do
    @client.create_invoice(num: '001', services: [])
    get '/invoices/widgets-inc/001/mark_sent'
    expect(@client.find_invoice('001').get_status).to eq('sent')
  end

  it 'create form pre-fills the number field with the next free number' do
    @client.create_invoice(num: '001', services: [])
    get '/invoices/widgets-inc/create'
    expect(last_response.body).to include('value="002"')
  end

  it 'does not overwrite an existing invoice when an explicit duplicate num is submitted' do
    @client.create_invoice(num: '001', services: [{ item: 'Original', desc: 'orig', qty: 1, cost: 100 }])

    post '/invoices/widgets-inc/create', { 'invoice[num]' => '001', 'invoice[invoice_date]' => '07/09/2026',
      'invoice[total_amount]' => '999', 'invoice[total_discount]' => '0', 'invoice[amount_paid]' => '0',
      'invoice[terms]' => 'Net 30', 'invoice[notes]' => 'thanks' }.merge(svc(0))

    expect(last_response.status).to eq(302)
    expect(@client.invoices.size).to eq(1)
    expect(@client.find_invoice('001').services.first.item).to eq('Original')
  end
end
