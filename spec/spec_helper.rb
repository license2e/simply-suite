# spec/spec_helper.rb
ENV['RACK_ENV'] = 'test' # non-development env so Sinatra's host_authorization doesn't reject Rack::Test's Host header

require 'tmpdir'
require 'fileutils'
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'store'
require 'rack' # request specs build their `app` via Rack::Builder.parse_file(config.ru)

module DataRootHelper
  def with_temp_data_root
    dir = Dir.mktmpdir('simply-suite-spec')
    prev = Store.instance_variable_get(:@data_root)
    Store.data_root = dir
    yield
  ensure
    Store.instance_variable_set(:@data_root, prev)
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end
end

RSpec.configure do |c|
  c.include DataRootHelper
  c.expect_with(:rspec) { |e| e.syntax = :expect }
end
