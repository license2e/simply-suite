#!/usr/bin/env ruby
# Generates a sample invoice PDF for README documentation.
# Usage: bundle exec ruby scripts/generate_invoice_pdf.rb

require 'fileutils'
require 'dotenv'
Dotenv.load

ENV['DATABASE_URL'] = 'sqlite://./db/screenshot.sqlite3'
ENV['SESSION_SECRET'] = 'pdf-script-session-secret-must-be-at-least-64-characters-long-padding'
ENV['RACK_ENV'] = 'development'

require 'sequel'
DB = Sequel.connect(ENV['DATABASE_URL'])
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path('../db/migrations', __dir__))

DB[:services].delete
DB[:invoices].delete
DB[:clients].delete
DB[:users].delete

$:.unshift File.expand_path('../lib', __dir__)

require 'bcrypt'
require_relative '../models/user'
require_relative '../models/models'

client = Client.new
client.title       = 'Acme Corporation'
client.client_prefix = 'ACM'
client.contact     = 'Jane Smith'
client.email       = 'jane@acmecorp.com'
client.street      = '1800 Camden Rd, Suite 200'
client.city        = 'Charlotte'
client.state       = 'NC'
client.zip         = '28203'
client.save

invoice = Invoice.create(
  client:         client,
  num:            '007',
  invoice_date:   Time.now,
  total_amount:   4750.00,
  total_discount: 0.0,
  amount_paid:    0.0,
  terms:          'Net 30 days',
  notes:          'Thank you for choosing Simply Suite. We appreciate your business.',
  is_complete:    true,
  approved_on:    Time.now,
  created_at:     Time.now,
  updated_at:     Time.now
)

Service.create(invoice: invoice, item: 'Strategy',    desc: 'Digital strategy & brand audit',         qty: 1,  cost: 1500.00, created_at: Time.now, updated_at: Time.now)
Service.create(invoice: invoice, item: 'Design',      desc: 'UI/UX design for 10 core screens',       qty: 1,  cost: 2000.00, created_at: Time.now, updated_at: Time.now)
Service.create(invoice: invoice, item: 'Development', desc: 'Frontend development @ $125/hr',         qty: 10, cost: 125.00,  created_at: Time.now, updated_at: Time.now)

require 'prawn'
require 'prawn/table'

public_path      = File.expand_path('../public', __dir__)
logopath_local   = File.join(public_path, 'css/images/logo.png')
address_x        = 35
invoice_header_x = 325
lineheight_y     = 12
font_size        = 9
font_width_assumed = 5

dest = File.expand_path('../docs/sample-invoice.pdf', __dir__)
FileUtils.mkdir_p(File.dirname(dest))

Prawn::Document.generate(dest) do |pdf|
  pdf.move_down 25
  pdf.font 'Helvetica'
  pdf.font_size font_size

  pdf.text_box 'EON Media Group, LLC',          at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y
  pdf.text_box '1800 Camden Rd. Suite 107/123', at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y
  pdf.text_box 'Charlotte, NC 28203',           at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y

  last_y = pdf.cursor
  pdf.move_cursor_to pdf.bounds.height
  pdf.image logopath_local, width: 125, position: :right if File.exist?(logopath_local)
  pdf.move_cursor_to last_y

  pdf.move_down 85
  last_y = pdf.cursor

  pdf.text_box invoice.client.name.to_s,                                                          at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y
  pdf.text_box invoice.client.contact.to_s,                                                       at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y
  pdf.text_box "#{invoice.client.street} #{invoice.client.street2}",                              at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y
  pdf.text_box "#{invoice.client.city}, #{invoice.client.state} #{invoice.client.zip}",           at: [address_x, pdf.cursor]

  pdf.move_cursor_to last_y

  header_data = [
    ['Invoice #',    "#{invoice.client.client_prefix}-#{invoice.num}"],
    ['Invoice Date', invoice.formatted_invoice_date],
    ['Balance',      "$#{invoice.formatted_final_amount} USD"]
  ]
  pdf.table(header_data, position: invoice_header_x, width: 215) do
    style(row(0..1).columns(0..1), padding: [2, 5, 2, 5], borders: [])
    style(row(2), background_color: 'e9e9e9', border_color: 'dddddd', font_style: :bold)
    style(column(1), align: :right)
    style(row(2).columns(0), borders: [:top, :left, :bottom])
    style(row(2).columns(1), borders: [:top, :right, :bottom])
  end

  pdf.move_down 45

  service_data = [['Item', 'Description', 'Unit Cost', 'Quantity', 'Line Total']]
  invoice.services.each do |s|
    service_data << [s.item.to_s, s.desc.to_s, "$#{s.formatted_cost}", s.qty.to_s, "$#{s.formatted_line_total}"]
  end
  service_data << [' ', ' ', ' ', ' ', ' ']

  pdf.table(service_data, width: pdf.bounds.width) do
    style(row(1..-1).columns(0..-1), padding: [4, 5, 4, 5], borders: [:bottom], border_color: 'dddddd')
    style(row(0), background_color: 'e9e9e9', border_color: 'dddddd', font_style: :bold)
    style(row(0).columns(0..-1), borders: [:top, :bottom])
    style(row(0).columns(0),  borders: [:top, :left, :bottom])
    style(row(0).columns(-1), borders: [:top, :right, :bottom])
    style(row(-1), border_width: 2)
    style(column(2..-1), align: :right)
    style(columns(0), width: 75)
    style(columns(1), width: 275)
  end

  pdf.move_down 1

  totals = []
  if invoice.total_discount.to_f > 0
    totals << ['Sub Total',     "$#{invoice.formatted_total_amount}"]
    totals << ["Discount -#{invoice.formatted_discount_percentage}%", "$#{invoice.formatted_total_discount}"]
    totals << ['Invoice Total', "$#{invoice.formatted_discount_total_amount}"]
  else
    totals << ['Invoice Total', "$#{invoice.formatted_total_amount}"]
  end
  totals << ['Amount Paid', "-$#{invoice.formatted_amount_paid}"]
  totals << ['Balance',     "$#{invoice.formatted_final_amount} USD"]

  pdf.table(totals, position: invoice_header_x, width: 215) do
    style(row(0), font_style: :bold)
    style(column(1), align: :right)
    if invoice.total_discount.to_f > 0
      style(row(0..3).columns(0..3), padding: [2, 5, 2, 5], borders: [])
      style(row(2), font_style: :bold, border_color: 'dddddd', borders: [:top])
      style(row(4), background_color: 'e9e9e9', border_color: 'dddddd', font_style: :bold)
      style(row(4).columns(0), borders: [:top, :left, :bottom])
      style(row(4).columns(1), borders: [:top, :right, :bottom])
    else
      style(row(0..1).columns(0..1), padding: [2, 5, 2, 5], borders: [])
      style(row(2), background_color: 'e9e9e9', border_color: 'dddddd', font_style: :bold)
      style(row(2).columns(0), borders: [:top, :left, :bottom])
      style(row(2).columns(1), borders: [:top, :right, :bottom])
    end
  end

  pdf.move_down 25

  pdf.table([['Terms'], [invoice.formatted_terms]], width: 275) do
    style(row(0..-1).columns(0..-1), padding: [1, 0, 1, 0], borders: [])
    style(row(0).columns(0), font_style: :bold)
  end

  pdf.move_down 15

  pdf.table([['Notes'], [invoice.formatted_notes]], width: 275) do
    style(row(0..-1).columns(0..-1), padding: [1, 0, 1, 0], borders: [])
    style(row(0).columns(0), font_style: :bold)
  end

  page_num = 'page 1 of 1'
  pdf.text_box page_num, at: [(pdf.bounds.width - (page_num.length * font_width_assumed)), 10]
end

puts "PDF saved to docs/sample-invoice.pdf"

File.delete('db/screenshot.sqlite3') if File.exist?('db/screenshot.sqlite3')
