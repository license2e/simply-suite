#!/usr/bin/env ruby
# Generates a sample invoice PDF for README documentation.
# Usage: bundle exec ruby scripts/generate_invoice_pdf.rb

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'store'
require 'tmpdir'
Store.data_root = Dir.mktmpdir('sample')
biz = Store::Business.create(name: 'Your Company, LLC', contact: 'Your Name', email: 'billing@you.com',
                             street: '123 Main St', city: 'Charlotte', state: 'NC', zip: '28203')
client = biz.create_client(name: 'Acme Corporation', prefix: 'ACM', contact: 'Jane', email: 'jane@acme.com',
                           street: '456 Client Ave', street2: '', city: 'Charlotte', state: 'NC', zip: '28203')
inv = client.create_invoice(invoice_date: '2026-07-09', total_amount: 4750.0, terms: 'Net 30 days', notes: 'Thank you',
  services: [{ item: 'Strategy', desc: 'Digital strategy & brand audit', service_date: '2026-07-01', qty: 1, cost: 1500 }])
out = File.expand_path('../docs/sample-invoice.pdf', __dir__)
Store::InvoicePdf.render(inv, biz, out)
puts "Wrote #{out}"
