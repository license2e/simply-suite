# Setup root path
root = File.dirname(File.dirname(__FILE__))
config_path = File.expand_path("config", root)
$:.unshift config_path

require 'app_settings'
#script_log_path = File.join(root, 'logs/script-debug.log')

#log = File.new(script_log_path, "a")
#STDOUT.reopen(log)
#STDERR.reopen(log)

require 'rubygems'
require 'haml'
require 'data_mapper'
require 'action_mailer'

puts ""
puts "Started processing script: #{Time.now.strftime("%m/%d/%Y %H:%M:%S")}"
puts ""

# Setup paths
public_path = File.join(root, '/public')
models_path = File.join(root,'/models/models.rb')
configure_path = File.join(root,'/lib/app/configure.rb')
mailman_path = File.join(root,'/lib/app/mailman.rb')
datamapper_log_path = File.join(root,'logs/datamapper-debug.log')
haml_html_path = File.join(root,'views/invoices/html_email.haml')
haml_text_path = File.join(root,'views/invoices/text_email.haml')

# Email & Database defaults
require configure_path

# Database local
require models_path
DataMapper::Logger.new(datamapper_log_path, :debug)
#DataMapper.auto_upgrade!
DataMapper::Model.raise_on_save_failure = true
DataMapper.finalize

#=begin

invoices = Invoice.all(:is_complete => true, :approved_on.not => nil, :sent_at => nil, :paid_at => nil, :invoice_date.lt => Time.now )

if invoices != [] then
  # Mailman
  require mailman_path
  
  puts "starting [ "
  
  invoices.each do |invoice|
    
    email_options = {}
    email_options[:invoice] = invoice
    email_options[:html_body] = Haml::Engine.new(File.read(haml_html_path)).render(Object.new, {:@invoice => invoice})
    email_options[:text_body] = Haml::Engine.new(File.read(haml_text_path)).render(Object.new, {:@invoice => invoice})
    email_options[:public_path] = public_path
        
    Mailman.invoice(email_options).deliver
    puts " sent: #{invoice.client.client_prefix}-#{invoice.num} - $#{invoice.formatted_final_amount} USD to #{invoice.client.email}"
    
    if invoice.sent_at.nil? then
      begin
        invoice.update({:sent_at => Time.now})
      rescue DataMapper::SaveFailureError => e
        raise "#{e.to_s} -- validation(s): #{invoice.errors.values.join(', ')}"
      rescue StandardError => e
        raise "#{e.to_s}"
      end
    end
    
  end

else 
  
  puts "none to process [ "
  
end
#=end

puts "] done!"
puts ""
puts "Ended processing script: #{Time.now.strftime("%m/%d/%Y %H:%M:%S")}"
puts ""