#!/usr/bin/env ruby
# Generates a PDF invoice from a JSON file.
# Usage: bundle exec ruby scripts/invoice_from_json.rb path/to/invoice.json
# Output: PDF saved alongside the JSON file with the same basename.

require 'json'
require 'date'
require 'fileutils'
require 'prawn'
require 'prawn/table'

json_path = ARGV[0]
abort "Usage: bundle exec ruby #{File.basename($0)} <invoice.json>" unless json_path
abort "File not found: #{json_path}" unless File.exist?(json_path)

data = JSON.parse(File.read(json_path), symbolize_names: true)

services = data[:services].map do |s|
  s.merge(line_total: s[:qty].to_f * s[:unit_cost].to_f)
end

subtotal     = services.sum { |s| s[:line_total] }
discount_pct = data[:discount_percentage].to_f
discount_amt = (subtotal * discount_pct / 100.0).round(2)
total        = (subtotal - discount_amt).round(2)
amount_paid  = data[:amount_paid].to_f
balance      = (total - amount_paid).round(2)

fmt = ->(n) { format('%.2f', n) }
invoice_date = begin
  Date.parse(data[:invoice][:date].to_s).strftime('%B %d, %Y')
rescue ArgumentError
  data[:invoice][:date].to_s
end

logo_path = File.expand_path(data[:logo].to_s)

out_path = File.join(
  File.dirname(File.expand_path(json_path)),
  "#{File.basename(json_path, File.extname(json_path))}.pdf"
)

address_x        = 35
invoice_header_x = 325
lineheight_y     = 12
font_size        = 9
font_width_assumed = 5

Prawn::Document.generate(out_path) do |pdf|
  pdf.move_down 25
  pdf.font 'Helvetica'
  pdf.font_size font_size

  from = data[:from]
  pdf.text_box from[:company].to_s,        at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y
  pdf.text_box from[:address].to_s,        at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y
  pdf.text_box from[:city_state_zip].to_s, at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y

  last_y = pdf.cursor
  pdf.move_cursor_to pdf.bounds.height
  pdf.image logo_path, width: 125, position: :right if File.exist?(logo_path)
  pdf.move_cursor_to last_y

  pdf.move_down 85
  last_y = pdf.cursor

  bill_to = data[:bill_to]
  pdf.text_box bill_to[:name].to_s,    at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y
  pdf.text_box bill_to[:contact].to_s, at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y
  street = [bill_to[:street], bill_to[:street2]].map(&:to_s).reject(&:empty?).join(' ')
  pdf.text_box street,                 at: [address_x, pdf.cursor]
  pdf.move_down lineheight_y
  pdf.text_box "#{bill_to[:city]}, #{bill_to[:state]} #{bill_to[:zip]}", at: [address_x, pdf.cursor]

  pdf.move_cursor_to last_y

  inv = data[:invoice]
  header_data = [
    ['Invoice #',    inv[:number].to_s],
    ['Invoice Date', invoice_date],
    ['Balance',      "$#{fmt.call(balance)} USD"]
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
  services.each do |s|
    service_data << [
      s[:item].to_s, s[:description].to_s,
      "$#{fmt.call(s[:unit_cost])}", s[:qty].to_s, "$#{fmt.call(s[:line_total])}"
    ]
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
  if discount_pct > 0
    totals << ['Sub Total',      "$#{fmt.call(subtotal)}"]
    totals << ["Discount -#{discount_pct.to_i}%", "$#{fmt.call(discount_amt)}"]
    totals << ['Invoice Total',  "$#{fmt.call(total)}"]
  else
    totals << ['Invoice Total',  "$#{fmt.call(total)}"]
  end
  totals << ['Amount Paid', "-$#{fmt.call(amount_paid)}"]
  totals << ['Balance',     "$#{fmt.call(balance)} USD"]

  pdf.table(totals, position: invoice_header_x, width: 215) do
    style(row(0), font_style: :bold)
    style(column(1), align: :right)
    if discount_pct > 0
      style(row(0..3).columns(0..1), padding: [2, 5, 2, 5], borders: [])
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

  unless inv[:terms].to_s.empty?
    pdf.table([['Terms'], [inv[:terms].to_s]], width: 275) do
      style(row(0..-1).columns(0..-1), padding: [1, 0, 1, 0], borders: [])
      style(row(0).columns(0), font_style: :bold)
    end
    pdf.move_down 15
  end

  unless inv[:notes].to_s.empty?
    pdf.table([['Notes'], [inv[:notes].to_s]], width: 275) do
      style(row(0..-1).columns(0..-1), padding: [1, 0, 1, 0], borders: [])
      style(row(0).columns(0), font_style: :bold)
    end
  end

  page_num = 'page 1 of 1'
  pdf.text_box page_num, at: [(pdf.bounds.width - (page_num.length * font_width_assumed)), 10]
end

puts "PDF saved to #{out_path}"
