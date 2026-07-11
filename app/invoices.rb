require 'prawn'
require 'prawn/table'
require 'mailer'

class Invoices < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { authorize! }

  get '/:client_key?' do
    halt 404 unless params[:client_key]
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    per_page = 20
    @page = [params[:page].to_i, 1].max
    @total_pages = (Invoice.where(client_id: @client.id).count.to_f / per_page).ceil
    @invoices = Invoice.where(client_id: @client.id).order(Sequel.desc(:id)).limit(per_page).offset((@page - 1) * per_page).all
    @pagination_path = "/invoices/#{@client.client_key}"
    @page_title = "Invoices — #{@client.name}"
    v :'invoices/list'
  end

  get '/create/:client_key' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    @invoice = Invoice.new
    @services = [Service.new]
    @action_url = url("/create/#{@client.client_key}")
    @submit_value = 'Create Invoice'
    @page_title = "New Invoice — #{@client.name}"
    v :'invoices/create'
  end

  get '/edit/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    @client = @invoice.client
    @services = @invoice.services
    @services = [Service.new] if @services.empty?
    @action_url = url("/update/#{@invoice.id}")
    @submit_value = 'Update Invoice'
    @page_title = "Edit Invoice — #{@client.name}"
    v :'invoices/edit'
  end

  post '/create/:client_key' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    @invoice = Invoice.new(gather_invoice_data(params[:invoice]))
    @invoice.client = @client
    begin
      @invoice.save
    rescue Sequel::ValidationFailed => e
      flash[:error] = e.message
      redirect url("/create/#{@client.client_key}")
    end
    process_invoice_services(params[:invoice], @invoice)
    if validate_invoice(@invoice)
      create_invoice_pdf(settings.public_folder, @invoice, '/css/images/logo.png', Company.first)
      flash[:success] = "Invoice created successfully"
      redirect url("/#{@invoice.client.client_key}")
    end
    flash[:error] = "Please enter all required fields"
    redirect url("/edit/#{@invoice.id}")
  end

  post '/update/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    begin
      @invoice.update(gather_invoice_data(params[:invoice]))
    rescue Sequel::ValidationFailed => e
      flash[:error] = e.message
      redirect url("/edit/#{@invoice.id}")
    end
    process_invoice_services(params[:invoice], @invoice)
    if validate_invoice(@invoice)
      create_invoice_pdf(settings.public_folder, @invoice, '/css/images/logo.png', Company.first)
      flash[:success] = "Invoice updated successfully"
      redirect url("/#{@invoice.client.client_key}")
    end
    flash[:error] = "Please enter all required fields"
    redirect url("/edit/#{@invoice.id}")
  end

  get '/:client_key/:invoice_number' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    num = params[:invoice_number].delete_prefix("#{@client.client_prefix}-")
    @invoice = Invoice.first(client_id: @client.id, num: num)
    halt 404 unless @invoice
    @company = Company.first
    @logopath = '/css/images/logo.png'
    pdf_paths = get_invoice_pdf_path(settings.public_folder, @invoice)
    @pdf_invoice_path = File.exist?(pdf_paths[:local]) ? pdf_paths[:web] : nil
    @smtp_configured = smtp_configured?
    @page_title = "Invoice #{@client.client_prefix}-#{@invoice.num} — #{@client.name}"
    v :'invoices/view'
  end

  get '/:client_key/:invoice_number/preview' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    num = params[:invoice_number].delete_prefix("#{@client.client_prefix}-")
    @invoice = Invoice.first(client_id: @client.id, num: num)
    halt 404 unless @invoice
    @company = Company.first
    logo_local = File.join(settings.public_folder, 'css/images/logo.png')
    @logo_url = File.exist?(logo_local) ? "/css/images/logo.png?v=#{File.mtime(logo_local).to_i}" : nil
    erb :'invoices/preview', layout: false
  end

  get '/delete/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    halt 403 unless @invoice.deletable?
    client_key = @invoice.client.client_key
    @invoice.soft_delete
    flash[:success] = "Invoice deleted."
    redirect url("/#{client_key}")
  end

  get '/approve/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    @invoice.update(approved_on: Time.now) if @invoice.approved_on.nil?
    flash[:success] = "Invoice approved!"
    redirect invoice_view_url(@invoice)
  end

  get '/send/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    unless smtp_configured?
      flash[:error] = "SMTP is not configured — cannot send email"
      redirect invoice_view_url(@invoice)
    end
    html_body = erb :'invoices/html_email', layout: false
    text_body = erb :'invoices/text_email', layout: false
    pdf_paths = get_invoice_pdf_path(settings.public_folder, @invoice)
    Mailer.invoice(@invoice, html_body: html_body, text_body: text_body, pdf_path: pdf_paths[:local])
    @invoice.update(sent_at: Time.now) if @invoice.sent_at.nil?
    flash[:success] = "Invoice sent successfully!"
    redirect invoice_view_url(@invoice)
  end

  get '/mark_sent/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    @invoice.update(sent_at: Time.now) if @invoice.sent_at.nil?
    flash[:success] = "Invoice marked as sent!"
    redirect invoice_view_url(@invoice)
  end

  get '/paid/:id' do
    @invoice = Invoice[params[:id].to_i]
    halt 404 unless @invoice
    @invoice.update(paid_at: Time.now) if @invoice.paid_at.nil?
    flash[:success] = "Invoice marked as paid!"
    redirect invoice_view_url(@invoice)
  end

  helpers do
    def invoice_view_url(invoice)
      url("/#{invoice.client.client_key}/#{invoice.client.client_prefix}-#{invoice.num}")
    end

    def process_invoice_services(invoice_data, invoice)
      return unless invoice_data[:services]
      invoice_data[:services].each do |_key, s|
        if s[:service_id] && !s[:service_id].empty?
          serv = Service.first(id: s[:service_id].to_i, invoice_id: invoice.id)
          serv.update(
            item:         s[:item].empty? ? nil : s[:item],
            desc:         s[:desc].empty? ? nil : s[:desc],
            service_date: s[:service_date].empty? ? nil : DateTime.strptime(s[:service_date], "%m/%d/%Y"),
            qty:          s[:qty].empty? ? nil : s[:qty].to_f,
            cost:         s[:cost].empty? ? nil : s[:cost].to_f
          ) if serv
        else
          next if s[:item].empty? && s[:desc].empty?
          Service.create(
            invoice_id:   invoice.id,
            item:         s[:item].empty? ? nil : s[:item],
            desc:         s[:desc].empty? ? nil : s[:desc],
            service_date: s[:service_date].empty? ? nil : DateTime.strptime(s[:service_date], "%m/%d/%Y"),
            qty:          s[:qty].empty? ? nil : s[:qty].to_f,
            cost:         s[:cost].empty? ? nil : s[:cost].to_f
          )
        end
      end

      if invoice_data[:delete_services]
        invoice_data[:delete_services].each do |id|
          serv = Service.first(id: id.to_i, invoice_id: invoice.id)
          serv&.destroy
        end
      end
    end

    def gather_invoice_data(d)
      {
        num:            d[:num].empty? ? nil : d[:num],
        invoice_date:   d[:invoice_date].empty? ? nil : DateTime.strptime(d[:invoice_date], "%m/%d/%Y"),
        total_amount:   d[:total_amount].empty? ? 0.0 : d[:total_amount].gsub(/[^\d.]/, '').to_f,
        total_discount: d[:total_discount].empty? ? 0.0 : d[:total_discount].gsub(/[^\d.]/, '').to_f,
        amount_paid:    d[:amount_paid].empty? ? 0.0 : d[:amount_paid].gsub(/[^\d.]/, '').to_f,
        terms:          d[:terms],
        notes:          d[:notes],
        approved_on:    nil
      }
    end

    def validate_invoice(invoice)
      return false unless invoice.client_id && invoice.total_amount && invoice.num
      invoice.update(is_complete: true)
      true
    end

    def get_invoice_pdf_path(public_path, invoice)
      web_path  = "/pdfs/#{invoice.client.client_key}"
      local_dir = File.join(public_path, web_path)
      FileUtils.mkdir_p(local_dir)
      filename       = "#{invoice.client.client_prefix}-#{invoice.num}.pdf"
      {
        local:    File.join(local_dir, filename),
        web:      File.join(web_path, filename),
        web_path: web_path
      }
    end

    def create_invoice_pdf(public_path, invoice, logopath, company = nil)
      paths = get_invoice_pdf_path(public_path, invoice)
      local_file = paths[:local]

      Prawn::Document.generate(local_file) do |pdf|
        logopath_local = File.join(public_path, logopath)
        address_x          = 35
        invoice_header_x   = 325
        lineheight_y       = 12
        font_size          = 9
        font_width_assumed = 5

        pdf.move_down 25
        pdf.font "Helvetica"
        pdf.font_size font_size

        if company
          pdf.text_box company.name.to_s,      at: [address_x, pdf.cursor]
          pdf.move_down lineheight_y
          unless company.contact.to_s.empty?
            pdf.text_box company.contact.to_s, at: [address_x, pdf.cursor]
            pdf.move_down lineheight_y
          end
          pdf.text_box company.street.to_s,    at: [address_x, pdf.cursor]
          pdf.move_down lineheight_y
          pdf.text_box company.city_state_zip,  at: [address_x, pdf.cursor]
          pdf.move_down lineheight_y
          unless company.email.to_s.empty?
            pdf.text_box company.email.to_s,   at: [address_x, pdf.cursor]
            pdf.move_down lineheight_y
          end
        end

        last_y = pdf.cursor
        pdf.move_cursor_to pdf.bounds.height
        pdf.image logopath_local, width: 125, position: :right if File.exist?(logopath_local)
        pdf.move_cursor_to last_y

        pdf.move_down 85
        last_y = pdf.cursor

        pdf.text_box invoice.client.name.to_s,    at: [address_x, pdf.cursor]
        pdf.move_down lineheight_y
        pdf.text_box invoice.client.contact.to_s, at: [address_x, pdf.cursor]
        pdf.move_down lineheight_y
        pdf.text_box "#{invoice.client.street} #{invoice.client.street2}".strip, at: [address_x, pdf.cursor]
        pdf.move_down lineheight_y
        pdf.text_box "#{invoice.client.city}, #{invoice.client.state} #{invoice.client.zip}", at: [address_x, pdf.cursor]
        pdf.move_down lineheight_y
        pdf.text_box invoice.client.email.to_s,   at: [address_x, pdf.cursor]

        pdf.move_cursor_to last_y

        header_data = [
          ["Invoice #",    "#{invoice.client.client_prefix}-#{invoice.num}"],
          ["Invoice Date", invoice.formatted_invoice_date],
          ["Balance",      "$#{invoice.formatted_final_amount} USD"]
        ]
        pdf.table(header_data, position: invoice_header_x, width: 215) do
          style(row(0..1).columns(0..1), padding: [2, 5, 2, 5], borders: [])
          style(row(2), background_color: 'e9e9e9', border_color: 'dddddd', font_style: :bold)
          style(column(1), align: :right)
          style(row(2).columns(0), borders: [:top, :left, :bottom])
          style(row(2).columns(1), borders: [:top, :right, :bottom])
        end

        pdf.move_down 45

        service_data = [["Item", "Description", "Date", "Unit Cost", "Qty", "Line Total"]]
        invoice.services.each do |s|
          service_data << [s.item.to_s, s.desc.to_s, s.formatted_service_date, "$#{s.formatted_cost}", s.qty.to_s, "$#{s.formatted_line_total}"]
        end
        service_data << [" ", " ", " ", " ", " ", " "]

        pdf.table(service_data, width: pdf.bounds.width) do
          style(row(1..-1).columns(0..-1), padding: [4, 5, 4, 5], borders: [:bottom], border_color: 'dddddd')
          style(row(0), background_color: 'e9e9e9', border_color: 'dddddd', font_style: :bold)
          style(row(0).columns(0..-1), borders: [:top, :bottom])
          style(row(0).columns(0),  borders: [:top, :left, :bottom])
          style(row(0).columns(-1), borders: [:top, :right, :bottom])
          style(row(-1), border_width: 2)
          style(column(2..-1), align: :right)
          style(columns(0), width: 65)
          style(columns(1), width: 200)
          style(columns(2), width: 65)
        end

        pdf.move_down 1

        totals = []
        if invoice.total_discount.to_f > 0
          totals << ["Sub Total",      "$#{invoice.formatted_total_amount}"]
          totals << ["Discount -#{invoice.formatted_discount_percentage}%", "$#{invoice.formatted_total_discount}"]
          totals << ["Invoice Total",  "$#{invoice.formatted_discount_total_amount}"]
        else
          totals << ["Invoice Total",  "$#{invoice.formatted_total_amount}"]
        end
        totals << ["Amount Paid", "-$#{invoice.formatted_amount_paid}"]
        totals << ["Balance",     "$#{invoice.formatted_final_amount} USD"]

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

        pdf.table([["Terms"], [invoice.formatted_terms]], width: 275) do
          style(row(0..-1).columns(0..-1), padding: [1, 0, 1, 0], borders: [])
          style(row(0).columns(0), font_style: :bold)
        end

        pdf.move_down 15

        pdf.table([["Notes"], [invoice.formatted_notes]], width: 275) do
          style(row(0..-1).columns(0..-1), padding: [1, 0, 1, 0], borders: [])
          style(row(0).columns(0), font_style: :bold)
        end

        page_num = "page 1 of 1"
        pdf.text_box page_num, at: [(pdf.bounds.width - (page_num.length * font_width_assumed)), 10]
      end

      paths[:web]
    end
  end
end
