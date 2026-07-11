# spec/scripts/export_to_json_spec.rb
require 'spec_helper'
require 'sequel'

RSpec.describe 'export_to_json' do
  around { |ex| with_temp_data_root { ex.run } }

  it 'exports company, clients, invoices+services and timesheets' do
    db = Sequel.sqlite
    db.create_table(:companies) { primary_key :id; String :name; String :contact; String :email; String :street; String :city; String :state; String :zip }
    db.create_table(:clients) { primary_key :id; String :client_key; String :client_prefix; String :name; String :contact; String :email; String :street; String :street2; String :city; String :state; String :zip; DateTime :deleted_at }
    db.create_table(:invoices) { primary_key :id; Integer :client_id; String :num; DateTime :invoice_date; Float :total_amount; Float :total_discount; Float :amount_paid; TrueClass :is_complete; String :terms; String :notes; DateTime :approved_on; DateTime :sent_at; DateTime :paid_at; DateTime :deleted_at }
    db.create_table(:services) { primary_key :id; Integer :invoice_id; String :item; String :desc; DateTime :service_date; Float :qty; Float :cost }
    db.create_table(:timesheets) { primary_key :id; Integer :client_id; Integer :invoice_id; String :item; String :desc; DateTime :service_date; Float :qty; Float :cost; TrueClass :invoiced }
    db[:companies].insert(name: 'Acme LLC', contact: 'Me', email: 'a@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203')
    cid = db[:clients].insert(client_key: 'widgets-inc', client_prefix: 'WID', name: 'Widgets Inc', contact: 'J', email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203')
    iid = db[:invoices].insert(client_id: cid, num: '001', invoice_date: Time.new(2026,7,9), total_amount: 250.0, total_discount: 0, amount_paid: 0, is_complete: true, terms: 'Net 30', notes: 'ty')
    db[:services].insert(invoice_id: iid, item: 'Dev', desc: 'x', service_date: Time.new(2026,7,5), qty: 2, cost: 125)
    db[:timesheets].insert(client_id: cid, invoice_id: iid, item: 'Dev', desc: 'x', service_date: Time.new(2026,7,5), qty: 2, cost: 125, invoiced: true)

    load File.expand_path('../../scripts/export_to_json.rb', __dir__)
    ExportToJson.run(db, Store.data_root)

    biz = Store::Business.all.first
    expect(biz.name).to eq('Acme LLC')
    client = biz.find_client('widgets-inc')
    expect(client.prefix).to eq('WID')
    inv = client.find_invoice('001')
    expect(inv.services.first.item).to eq('Dev')
    ts = client.timesheet_period('2026-07').entries.first
    expect(ts[:invoiced]).to be true
    expect(ts[:invoice_num]).to eq('001')
  end
end
