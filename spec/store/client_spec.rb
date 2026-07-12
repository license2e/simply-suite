require 'spec_helper'

RSpec.describe Store::Client do
  around { |ex| with_temp_data_root { ex.run } }

  let(:biz) do
    Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com',
                           street: '1', city: 'CLT', state: 'NC', zip: '28203')
  end

  let(:cattrs) do
    { name: 'Widgets Inc', prefix: 'WID', contact: 'Jane', email: 'j@w.com',
      street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203' }
  end

  it 'creates a client with a slug and client.json' do
    c = biz.create_client(cattrs)
    expect(c.slug).to eq('widgets-inc')
    expect(c.prefix).to eq('WID')
    expect(File.exist?(File.join(c.dir, 'client.json'))).to be true
    expect(biz.find_client('widgets-inc').name).to eq('Widgets Inc')
    expect(biz.clients.map(&:slug)).to eq(['widgets-inc'])
  end

  it 'inherits the business timesheet period unless overridden' do
    c = biz.create_client(cattrs)
    expect(c.resolved_timesheet_period).to eq('monthly')
    c.update(timesheet_period: 'weekly')
    expect(biz.find_client(c.slug).resolved_timesheet_period).to eq('weekly')
  end

  it 'soft-deletes by moving the folder into clients/archive' do
    c = biz.create_client(cattrs)
    c.soft_delete
    expect(biz.find_client('widgets-inc')).to be_nil
    expect(File.exist?(File.join(biz.dir, 'clients', 'archive', 'widgets-inc', 'client.json'))).to be true
  end

  it 'reserves the "archive" and "create" slugs so clients cannot collide with them' do
    c1 = biz.create_client(cattrs.merge(name: 'Archive'))
    expect(c1.slug).not_to eq('archive')

    c2 = biz.create_client(cattrs.merge(name: 'Create'))
    expect(c2.slug).not_to eq('create')
  end

  it 'stores a sanitized per-client default rate (nil when blank)' do
    c = biz.create_client(cattrs)
    expect(c.default_rate).to be_nil
    c.update(default_rate: '$125.00')
    expect(biz.find_client(c.slug).default_rate).to eq('125.00')
    c.update(default_rate: '')
    expect(biz.find_client(c.slug).default_rate).to be_nil
  end
end
