require 'spec_helper'
require 'rack/test'

RSpec.describe 'Health', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end

  it 'returns 200 ok at /health' do
    get '/health'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq('ok')
  end
end
