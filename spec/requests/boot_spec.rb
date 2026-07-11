require 'spec_helper'
require 'rack/test'

RSpec.describe 'Boot', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end

  around { |ex| with_temp_data_root { ex.run } }

  it 'redirects to /businesses when no business is selected' do
    get '/'
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include('/businesses')
  end
end
