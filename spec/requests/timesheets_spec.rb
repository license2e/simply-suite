# spec/requests/timesheets_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Timesheets', type: :request do
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

  it 'saves entries into a period and rolls them into an invoice' do
    post '/timesheets/widgets-inc?period=2026-07',
         'entries[0][item]' => 'Dev', 'entries[0][desc]' => 'x',
         'entries[0][service_date]' => '07/05/2026', 'entries[0][qty]' => '2', 'entries[0][cost]' => '125'
    expect(@client.timesheet_period('2026-07').entries.size).to eq(1)

    post '/timesheets/widgets-inc/invoice?period=2026-07'
    expect(@client.invoices.size).to eq(1)
    expect(@client.timesheet_summary).to eq(total: 1, uninvoiced: 0)
  end
end
