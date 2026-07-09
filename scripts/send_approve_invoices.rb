root = File.dirname(File.dirname(__FILE__))
$:.unshift File.join(root, 'lib')
$:.unshift File.join(root, 'config')

require 'dotenv'
Dotenv.load(File.join(root, '.env'))

require 'sequel'
DB = Sequel.connect(ENV.fetch('DATABASE_URL'))

require 'mail'
if ENV['SMTP_HOST'] && !ENV['SMTP_HOST'].empty?
  Mail.defaults do
    delivery_method :smtp, {
      address:              ENV['SMTP_HOST'],
      port:                 (ENV['SMTP_PORT'] || 587).to_i,
      user_name:            ENV['SMTP_USERNAME'],
      password:             ENV['SMTP_PASSWORD'],
      enable_starttls_auto: true
    }
  end
end

require_relative '../models/models'
require 'mailer'

views_root = File.join(root, 'views')

puts "Started: #{Time.now.strftime("%m/%d/%Y %H:%M:%S")}"

invoices = Invoice.where(
  is_complete: true,
  sent_at: nil,
  paid_at: nil
).exclude(approved_on: nil).where { invoice_date < Time.now }.all

if invoices.empty?
  puts "None to process."
else
  invoices.each do |invoice|
    ctx = Object.new
    ctx.instance_variable_set(:@invoice, invoice)
    b = ctx.instance_eval { binding }
    html_body = ERB.new(File.read(File.join(views_root, 'invoices/html_email.erb'))).result(b)
    text_body = ERB.new(File.read(File.join(views_root, 'invoices/text_email.erb'))).result(b)
    public_path = File.join(root, 'public')

    web_path  = "/pdfs/#{invoice.client.client_key}"
    local_dir = File.join(public_path, web_path)
    filename  = "#{invoice.client.client_prefix}-#{invoice.num}.pdf"
    pdf_path  = File.join(local_dir, filename)

    Mailer.invoice(invoice, html_body: html_body, text_body: text_body, pdf_path: pdf_path)
    puts "  Sent: #{invoice.client.client_prefix}-#{invoice.num} to #{invoice.client.email}"
    invoice.update(sent_at: Time.now) if invoice.sent_at.nil?
  end
end

puts "Done: #{Time.now.strftime("%m/%d/%Y %H:%M:%S")}"
