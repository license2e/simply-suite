# spec/requests/settings_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Settings', type: :request do
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
  before { post "/businesses/#{@biz.slug}/select" }

  it 'updates company info and the default timesheet period' do
    post '/settings/company', company: { name: 'Biz 2', contact: 'C2', email: 'b2@x.com',
                                         street: '9', city: 'CLT', state: 'NC', zip: '28204',
                                         timesheet_period: 'weekly', terms: 'Net 15', notes: 'ty' }
    b = Store::Business.find(@biz.slug)
    expect(b.name).to eq('Biz 2')
    expect(b.defaults[:timesheet_period]).to eq('weekly')
    expect(b.defaults[:terms]).to eq('Net 15')
  end
end
