require 'spec_helper'

RSpec.describe Store::TimesheetPeriod do
  around { |ex| with_temp_data_root { ex.run } }

  let(:biz) { Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203') }
  let(:client) { biz.create_client(name: 'Widgets Inc', prefix: 'WID', contact: 'J', email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203') }

  it 'computes period keys per granularity' do
    d = Date.new(2026, 7, 5)
    expect(described_class.key_for(d, 'daily')).to eq('2026-07-05')
    expect(described_class.key_for(d, 'monthly')).to eq('2026-07')
    expect(described_class.key_for(d, 'quarterly')).to eq('2026-Q3')
    expect(described_class.key_for(d, 'weekly')).to eq('2026-W27')
  end

  it 'adds entries with generated ids and buckets by service_date' do
    p = client.timesheet_period('2026-07')
    p.apply(rows: [{ item: 'Dev', desc: 'x', service_date: '2026-07-05', qty: 2, cost: 125 }], deletes: [])
    reloaded = client.timesheet_period('2026-07')
    expect(reloaded.entries.size).to eq(1)
    expect(reloaded.entries.first[:id]).to match(/\A[0-9a-f]{6}\z/)
    expect(client.timesheet_summary).to eq(total: 1, uninvoiced: 1)
  end

  it 're-buckets an entry into another period when its service_date changes' do
    client.timesheet_period('2026-07').apply(
      rows: [{ item: 'Dev', desc: 'x', service_date: '2026-07-05', qty: 1, cost: 100 }], deletes: []
    )
    id = client.timesheet_period('2026-07').entries.first[:id]
    client.timesheet_period('2026-07').apply(
      rows: [{ id: id, item: 'Dev', desc: 'x', service_date: '2026-08-03', qty: 1, cost: 100 }], deletes: []
    )
    expect(client.timesheet_period('2026-07').entries).to be_empty
    expect(client.timesheet_period('2026-08').entries.map { |e| e[:id] }).to eq([id])
  end

  it 'rolls a period into a draft invoice and marks entries invoiced' do
    p = client.timesheet_period('2026-07')
    p.apply(rows: [{ item: 'Dev', desc: 'x', service_date: '2026-07-05', qty: 2, cost: 125 }], deletes: [])
    inv = client.timesheet_period('2026-07').create_invoice
    expect(inv.num).to eq('001')
    expect(inv.services.first.item).to eq('Dev')
    expect(inv.total_amount).to eq(250.0)
    expect(client.timesheet_summary).to eq(total: 1, uninvoiced: 0)
    expect(client.timesheet_period('2026-07').create_invoice).to be_nil # nothing left
  end

  it 'un-invoices entries when the invoice is soft-deleted' do
    p = client.timesheet_period('2026-07')
    p.apply(rows: [{ item: 'Dev', desc: 'x', service_date: '2026-07-05', qty: 1, cost: 100 }], deletes: [])
    inv = client.timesheet_period('2026-07').create_invoice
    inv.soft_delete
    expect(client.timesheet_summary).to eq(total: 1, uninvoiced: 1)
  end
end
