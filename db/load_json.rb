require 'dotenv'
Dotenv.load

require 'sequel'
require 'json'
require 'date'

DB = Sequel.connect(ENV.fetch('DATABASE_URL'))
Sequel.extension :migration
Sequel.application_timezone = :utc
Sequel.database_timezone = :utc

require_relative '../models/models'

path = ARGV[0] || File.expand_path('../docs/invoice-template.json', __dir__)
abort "File not found: #{path}" unless File.exist?(path)

data = JSON.parse(File.read(path), symbolize_names: true)

from     = data[:from]
bill_to  = data[:bill_to]
inv      = data[:invoice]
services = data[:services] || []

# Parse "Charlotte, NC 28203" into components
def parse_city_state_zip(str)
  m = str.to_s.match(/\A(.+),\s*([A-Za-z]{2})\s+(\d+(?:-\d+)?)\z/)
  m ? { city: m[1].strip, state: m[2].upcase, zip: m[3] } : { city: str.to_s, state: '', zip: '' }
end

# Split invoice number like "ACM-001" into prefix + num
inv_parts  = inv[:number].to_s.split('-', 2)
inv_prefix = inv_parts[0] || 'INV'
inv_num    = inv_parts[1] || '001'

# ── Company ──────────────────────────────────────────────────────────────────
puts "\n── Company"
if Company.count > 0
  puts "   Skipping — company already exists (#{Company.first.name})"
  puts "   Run seeds.rb or update manually to change it."
else
  csz = parse_city_state_zip(from[:city_state_zip].to_s)
  company = Company.create(
    name:    from[:company],
    contact: from[:contact],
    email:   from[:email],
    street:  from[:address],
    city:    csz[:city],
    state:   csz[:state],
    zip:     csz[:zip]
  )
  puts "   Created: #{company.name}"
end

# ── Client ───────────────────────────────────────────────────────────────────
puts "\n── Client"
existing = Client.first(client_key: bill_to[:name].to_s.downcase.gsub(/[^\w\s-]/, '').gsub(/[\s_]+/, '-').gsub(/-+/, '-').gsub(/\A-|-\z/, ''))
if existing
  puts "   Skipping — client '#{existing.name}' already exists (#{existing.client_key})"
  client = existing
else
  client = Client.new
  client.title         = bill_to[:name]
  client.client_prefix = inv_prefix
  client.contact       = bill_to[:contact]
  client.email         = bill_to[:email]
  client.street        = bill_to[:street]
  client.street2       = bill_to[:street2].to_s
  client.city          = bill_to[:city]
  client.state         = bill_to[:state]
  client.zip           = bill_to[:zip].to_s
  client.save
  puts "   Created: #{client.name} (#{client.client_key}, prefix: #{client.client_prefix})"
end

# ── Invoice ───────────────────────────────────────────────────────────────────
puts "\n── Invoice"
existing_inv = Invoice.first(client_id: client.id, num: inv_num)
if existing_inv
  puts "   Skipping — invoice #{client.client_prefix}-#{inv_num} already exists"
  invoice = existing_inv
else
  total    = services.sum { |s| s[:qty].to_f * s[:unit_cost].to_f }
  discount = total * (data[:discount_percentage].to_f / 100.0)
  inv_date = (Date.parse(inv[:date].to_s) rescue Date.today)

  invoice = Invoice.create(
    client_id:      client.id,
    num:            inv_num,
    invoice_date:   inv_date,
    total_amount:   total,
    total_discount: discount,
    amount_paid:    data[:amount_paid].to_f,
    terms:          inv[:terms],
    notes:          inv[:notes],
    is_complete:    true
  )
  puts "   Created: #{client.client_prefix}-#{invoice.num} — $#{'%.2f' % total}"
end

# ── Services ──────────────────────────────────────────────────────────────────
puts "\n── Services"
if invoice.services.any?
  puts "   Skipping — invoice already has #{invoice.services.count} service(s)"
else
  services.each do |s|
    Service.create(
      invoice_id: invoice.id,
      item:       s[:item],
      desc:       s[:description],
      qty:        s[:qty].to_i,
      cost:       s[:unit_cost].to_f
    )
    puts "   #{s[:item]}: #{s[:qty]} x $#{'%.2f' % s[:unit_cost]}"
  end
end

puts "\n✓ Done"
puts "  Client:  /clients/view/#{client.client_key}"
puts "  Invoice: /invoices/#{client.client_key}/#{client.client_prefix}-#{invoice.num}"
