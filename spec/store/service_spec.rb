require 'spec_helper'

RSpec.describe Store::Service do
  it 'exposes fields and formatted helpers' do
    s = Store::Service.new(item: 'Dev', desc: 'work', service_date: '2026-07-05', qty: 2.0, cost: 125.0)
    expect(s.item).to eq('Dev')
    expect(s.service_date).to eq(Date.new(2026, 7, 5))
    expect(s.formatted_service_date).to eq('07/05/2026')
    expect(s.formatted_cost).to eq('125.00')
    expect(s.formatted_line_total).to eq('250.00')
  end

  it 'round-trips to_h with a date string and tolerates blanks' do
    s = Store::Service.new(item: 'X', desc: nil, service_date: nil, qty: 1, cost: 10)
    expect(s.formatted_service_date).to eq('')
    expect(s.to_h).to eq(item: 'X', desc: nil, service_date: nil, qty: 1.0, cost: 10.0)
  end
end
