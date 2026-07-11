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
      create_invoice_pdf(settings.public_folder, @invoice, Company.first)
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
      create_invoice_pdf(settings.public_folder, @invoice, Company.first)
      flash[:success] = "Invoice updated successfully"
      redirect url("/#{@invoice.client.client_key}")
    end
    flash[:error] = "Please enter all required fields"
    redirect url("/edit/#{@invoice.id}")
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

  # Wildcard routes last — must come after all specific action routes
  get '/:client_key/:invoice_number' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    num = params[:invoice_number].delete_prefix("#{@client.client_prefix}-")
    @invoice = Invoice.first(client_id: @client.id, num: num)
    halt 404 unless @invoice
    @company = Company.first
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
    logo = resolve_logo
    @logo_url = logo ? logo[:web] : nil
    erb :'invoices/preview', layout: false
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

    def create_invoice_pdf(public_path, invoice, company = nil)
      paths = get_invoice_pdf_path(public_path, invoice)
      local_file = paths[:local]
      logo = resolve_logo(public_path)

      Prawn::Document.generate(local_file) do |pdf|
        logopath_local = logo ? logo[:local] : nil
        w      = pdf.bounds.width
        base   = 9
        small  = 7
        lh     = 13
        gray   = '666666'
        lgray  = 'aaaaaa'
        half   = w * 0.50

        pdf.font "Helvetica"
        pdf.font_size base

        # ── HEADER ────────────────────────────────────────────────────────────
        header_top = pdf.cursor
        left_y     = header_top

        # Left: company info (text_box — no cursor movement)
        if company
          pdf.font("Helvetica", style: :bold) do
            pdf.text_box company.name.to_s, at: [0, left_y], width: half, size: 11
          end
          left_y -= 16
          pdf.fill_color gray
          [company.contact, company.street, company.city_state_zip, company.email].each do |line|
            next if line.to_s.strip.empty?
            pdf.text_box line.to_s, at: [0, left_y], width: half, size: base
            left_y -= lh
          end
          pdf.fill_color '000000'
        end

        # Right: logo → "INVOICE" → # → date → balance box (cursor flow)
        pdf.move_cursor_to header_top
        if logopath_local && File.exist?(logopath_local)
          pdf.image logopath_local, fit: [200, 55], position: :right
          pdf.move_down 6
        end
        pdf.font("Helvetica", style: :bold) { pdf.text "INVOICE", size: 22, align: :right }
        pdf.font("Helvetica", style: :bold) do
          pdf.text "#{invoice.client.client_prefix}-#{invoice.num}", size: base, align: :right
        end
        pdf.fill_color gray
        pdf.text invoice.formatted_invoice_date, size: base, align: :right
        pdf.fill_color '000000'
        pdf.move_down 8

        balance_w = 175
        pdf.table([["Balance Due", "$#{invoice.formatted_final_amount} USD"]], position: w - balance_w, width: balance_w) do
          style(row(0).columns(0..1), background_color: 'f5f5f5', border_color: 'e0e0e0',
                borders: [:top, :right, :bottom, :left], padding: [7, 8, 7, 8])
          style(column(0), font_style: :bold, size: small, text_color: lgray)
          style(column(1), font_style: :bold, size: 12, align: :right)
        end

        # Advance past both columns
        pdf.move_cursor_to [left_y, pdf.cursor].min - 16

        # ── BILL TO ───────────────────────────────────────────────────────────
        bill_top = pdf.cursor
        pdf.fill_color lgray
        pdf.font("Helvetica", style: :bold) { pdf.text_box "BILL TO", at: [0, bill_top], size: small }
        pdf.fill_color '000000'
        bill_top -= 12

        pdf.font("Helvetica", style: :bold) do
          pdf.text_box invoice.client.name.to_s, at: [0, bill_top], size: base
        end
        bill_top -= lh

        pdf.fill_color gray
        [
          invoice.client.contact,
          "#{invoice.client.street} #{invoice.client.street2}".strip,
          "#{invoice.client.city}, #{invoice.client.state} #{invoice.client.zip}",
          invoice.client.email
        ].each do |line|
          next if line.to_s.gsub(/[\s,]/, '').empty?
          pdf.text_box line.to_s, at: [0, bill_top], width: half, size: base
          bill_top -= lh
        end
        pdf.fill_color '000000'

        pdf.move_cursor_to bill_top - 18

        # ── SERVICES ──────────────────────────────────────────────────────────
        service_data = [["Item", "Description", "Date", "Unit Cost", "Qty", "Line Total"]]
        invoice.services.each do |s|
          service_data << [s.item.to_s, s.desc.to_s, s.formatted_service_date,
                           "$#{s.formatted_cost}", s.qty.to_s, "$#{s.formatted_line_total}"]
        end

        pdf.table(service_data, width: w) do
          style(row(0..-1).columns(0..-1), padding: [5, 6, 5, 6], border_width: 0)
          style(row(0), background_color: 'f9f9f9', font_style: :bold, size: small, text_color: lgray)
          style(row(1..-1).columns(0..-1), borders: [:bottom], border_color: 'f2f2f2')
          style(column(2..-1), align: :right)
          style(column(0), width: 65)
          style(column(1), width: 200)
          style(column(2), width: 65)
        end

        pdf.move_down 16

        # ── TOTALS ────────────────────────────────────────────────────────────
        totals_w = 220
        totals_x = w - totals_w

        if invoice.total_discount.to_f > 0
          pdf.table([["Subtotal", "$#{invoice.formatted_total_amount}"],
                     ["Discount (#{invoice.formatted_discount_percentage}%)", "-$#{invoice.formatted_total_discount}"]], position: totals_x, width: totals_w) do
            style(row(0..-1).columns(0..-1), padding: [3, 6, 3, 6], borders: [], text_color: gray)
            style(column(1), align: :right)
          end
          pdf.table([["Invoice Total", "$#{invoice.formatted_discount_total_amount}"]], position: totals_x, width: totals_w) do
            style(row(0).columns(0..1), padding: [4, 6, 4, 6], borders: [:top], border_color: 'e8e8e8', font_style: :bold, text_color: '111111')
            style(column(1), align: :right)
          end
        else
          pdf.table([["Invoice Total", "$#{invoice.formatted_total_amount}"]], position: totals_x, width: totals_w) do
            style(row(0).columns(0..1), padding: [3, 6, 3, 6], borders: [], font_style: :bold, text_color: '111111')
            style(column(1), align: :right)
          end
        end

        if invoice.amount_paid.to_f > 0
          pdf.table([["Amount Paid", "-$#{invoice.formatted_amount_paid}"]], position: totals_x, width: totals_w) do
            style(row(0).columns(0..1), padding: [3, 6, 3, 6], borders: [], text_color: gray)
            style(column(1), align: :right)
          end
        end

        pdf.table([["Balance Due", "$#{invoice.formatted_final_amount} USD"]], position: totals_x, width: totals_w) do
          style(row(0).columns(0..1), background_color: 'f5f5f5', border_color: 'e5e5e5',
                borders: [:top, :right, :bottom, :left], padding: [7, 8, 7, 8])
          style(column(0), font_style: :bold)
          style(column(1), font_style: :bold, size: 12, align: :right)
        end

        pdf.move_down 24

        # ── FOOTER: Terms | Notes side by side ────────────────────────────────
        col_w    = (w - 20) / 2.0
        footer_y = pdf.cursor

        pdf.fill_color lgray
        pdf.font("Helvetica", style: :bold) { pdf.text_box "Terms", at: [0, footer_y], size: small }
        pdf.fill_color '444444'
        pdf.text_box invoice.formatted_terms, at: [0, footer_y - 11], width: col_w, size: base

        pdf.fill_color lgray
        pdf.font("Helvetica", style: :bold) { pdf.text_box "Notes", at: [col_w + 20, footer_y], size: small }
        pdf.fill_color '444444'
        pdf.text_box invoice.formatted_notes, at: [col_w + 20, footer_y - 11], width: col_w, size: base
        pdf.fill_color '000000'
      end

      paths[:web]
    end
  end
end
