require 'mail'

class Mailer
  def self.invoice(invoice, html_body:, text_body:, pdf_path:)
    build(
      to: invoice.client.email,
      subject: "Invoice #{invoice.client.client_prefix}-#{invoice.num}"
    ) do |m|
      m.html_part do
        content_type 'text/html; charset=UTF-8'
        body html_body
      end
      m.text_part { body text_body }
      m.add_file pdf_path if File.exist?(pdf_path)
    end
  end

  def self.build(to:, subject:, &block)
    mail = Mail.new
    mail.from    = ENV.fetch('MAIL_FROM', 'noreply@example.com')
    mail.to      = to
    mail.subject = subject
    block.call(mail)
    mail.deliver!
  end
end
