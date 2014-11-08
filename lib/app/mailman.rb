class Mailman < ActionMailer::Base
  def invoice(options)
    
    invoice = options[:invoice]
    html_body = options[:html_body]
    text_body = options[:text_body]
    public_path = options[:public_path]
    
    invoice_web_path = "/pdfs/#{invoice.client.client_key}"
    invoice_local_path = File.join(public_path, invoice_web_path)
    FileUtils.mkdir_p(invoice_local_path)
    invoice_file_name = "#{invoice.client.client_prefix}-#{invoice.num}.pdf"
    invoice_local_file = File.join(invoice_local_path, invoice_file_name)
    invoice_web_file = File.join(invoice_web_path, invoice_file_name)
    
    attachments["#{invoice_file_name}"] = File.read("#{invoice_local_file}")
    
    mail(
      :to => "#{invoice.client.email}",
      :from => "from@example.com",
      :bcc => "bcc@example.com",
      :subject => "Invoice: #{invoice.client.client_prefix}-#{invoice.num} from EON Media Group"
    ) do |format|    
      format.text { text_body.to_s }
      format.html { html_body }
    end
    
    
  end
end
