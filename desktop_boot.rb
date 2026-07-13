# Boots the Simply Suite Sinatra app under Puma for the desktop shell.
# Works both in development (Gemfile bundle) and in a packaged app
# (a vendored `--standalone` bundle). Reads PORT from the environment.
ENV['RACK_ENV'] ||= 'production'

standalone = File.join(__dir__, 'vendor', 'bundle', 'bundler', 'setup.rb')
if File.exist?(standalone)
  require_relative 'vendor/bundle/bundler/setup'   # packaged: no bundler needed
else
  require 'bundler/setup'                           # development: use the Gemfile
end

require 'puma/cli'

port = ENV.fetch('PORT')
Puma::CLI.new([
  '-b', "tcp://127.0.0.1:#{port}",
  '-e', 'production',
  '--dir', __dir__               # loads ./config.ru relative to this file
]).run
