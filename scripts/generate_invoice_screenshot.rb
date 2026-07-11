#!/usr/bin/env ruby
# Generates a screenshot of the invoice view page for README documentation.
# Requirements: Chrome/Chromium installed, ferrum gem installed (bundle install)
# Usage: bundle exec ruby scripts/generate_invoice_screenshot.rb

require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'store'

ENV['SESSION_SECRET'] = 'screenshot-session-secret-must-be-at-least-64-characters-long-padding'
ENV['RACK_ENV'] = 'development'

# Use a dedicated, disposable data root for the sample business/client/invoice
Store.data_root = Dir.mktmpdir('screenshot')

biz = Store::Business.create(name: 'Simply Suite LLC', contact: 'Demo Admin', email: 'hello@simplysuite.com',
                             street: '1800 Camden Rd, Suite 107', city: 'Charlotte', state: 'NC', zip: '28203')
client = biz.create_client(name: 'Acme Corporation', prefix: 'ACM', contact: 'Jane Smith', email: 'jane@acmecorp.com',
                           street: '1800 Camden Rd, Suite 200', street2: '', city: 'Charlotte', state: 'NC', zip: '28203')
invoice = client.create_invoice(invoice_date: '2026-07-09', total_amount: 4750.0, terms: 'Net 30 days',
  notes: 'Thank you for choosing Simply Suite. We appreciate your business.',
  services: [
    { item: 'Strategy',    desc: 'Digital strategy & brand audit',   service_date: '2026-07-01', qty: 1,  cost: 1500.0 },
    { item: 'Design',      desc: 'UI/UX design for 10 core screens', service_date: '2026-07-03', qty: 1,  cost: 2000.0 },
    { item: 'Development', desc: 'Frontend development @ $125/hr',  service_date: '2026-07-05', qty: 10, cost: 125.0 }
  ])
Store::InvoicePdf.render(invoice, biz, invoice.pdf_path)

# Build the Rack app from the real config.ru (same app the server runs in production)
require 'rack'
built = Rack::Builder.parse_file(File.expand_path('../config.ru', __dir__))
app = built.is_a?(Array) ? built.first : built # Rack 2 returns [app, opts]; Rack 3 returns app

# Start Puma in a background thread
PORT = 9394
require 'puma'
require 'puma/configuration'
require 'puma/launcher'

server_thread = Thread.new do
  config = Puma::Configuration.new do |c|
    c.bind "tcp://127.0.0.1:#{PORT}"
    c.app app
    c.quiet
  end
  Puma::Launcher.new(config).run
end

# Wait for server to be ready
require 'net/http'
print 'Waiting for server'
30.times do
  begin
    Net::HTTP.get(URI("http://127.0.0.1:#{PORT}/businesses"))
    break
  rescue
    print '.'
    sleep 0.5
  end
end
puts ' ready!'

# Use Ferrum for screenshot
require 'ferrum'

browser = Ferrum::Browser.new(
  headless: true,
  window_size: [1280, 900],
  browser_options: { 'no-sandbox': nil }
)

begin
  # Select the business (sets session[:business] via a real form POST)
  browser.goto("http://127.0.0.1:#{PORT}/businesses")
  sleep 1
  browser.at_css('form button[type="submit"]').click
  sleep 1

  # Navigate to invoice view
  browser.goto("http://127.0.0.1:#{PORT}/invoices/#{client.slug}/#{invoice.num}")
  sleep 1.5

  # Remove fixed-height/overflow constraints so full page height is captured
  browser.execute(<<~JS)
    document.body.style.height = 'auto';
    document.body.style.overflow = 'visible';
    const inner = document.querySelector('body > div.flex-1');
    if (inner) { inner.style.overflow = 'visible'; inner.style.height = 'auto'; }
    const main = document.querySelector('main');
    if (main) { main.style.overflow = 'visible'; main.style.height = 'auto'; }
  JS

  # Take screenshot
  FileUtils.mkdir_p('docs')
  browser.screenshot(path: 'docs/invoice-screenshot.png', full: true)
  puts "Screenshot saved to docs/invoice-screenshot.png"
ensure
  browser.quit
  server_thread.kill
end
