require 'fileutils'

class Invoices < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { require_business! }

  helpers do
    def find_client!(key)
      c = current_business.find_client(key)
      halt(404) unless c
      c
    end

    def find_invoice!(client, num)
      i = client.find_invoice(num)
      halt(404) unless i
      i
    end

    def gather_invoice_data(d)
      { num: d[:num].to_s.empty? ? nil : d[:num],
        invoice_date: d[:invoice_date].to_s.empty? ? nil : Date.strptime(d[:invoice_date], '%m/%d/%Y'),
        total_amount: d[:total_amount].to_s.empty? ? 0.0 : d[:total_amount].gsub(/[^\d.]/, '').to_f,
        total_discount: d[:total_discount].to_s.empty? ? 0.0 : d[:total_discount].gsub(/[^\d.]/, '').to_f,
        amount_paid: d[:amount_paid].to_s.empty? ? 0.0 : d[:amount_paid].gsub(/[^\d.]/, '').to_f,
        terms: d[:terms], notes: d[:notes] }
    end

    def submitted_services(d)
      (d[:services] || {}).values.map do |s|
        { item: s[:item], desc: s[:desc],
          service_date: s[:service_date].to_s.empty? ? nil : Date.strptime(s[:service_date], '%m/%d/%Y'),
          qty: s[:qty], cost: s[:cost] }
      end
    end
  end

  get '/:client_key' do
    client = find_client!(params[:client_key])
    per_page = 20
    all = client.invoices
    @client = client
    @page = [params[:page].to_i, 1].max
    @total_pages = [(all.size.to_f / per_page).ceil, 1].max
    @invoices = all.slice((@page - 1) * per_page, per_page) || []
    @pagination_path = "/invoices/#{client.slug}"
    @page_title = "Invoices — #{client.name}"
    v :'invoices/list'
  end

  get '/:client_key/create' do
    @client = find_client!(params[:client_key])
    @invoice = Store::Invoice.new(@client, Store::Invoice.blank_data(''))
    @services = [Store::Service.new({})]
    @action_url = "/invoices/#{@client.slug}/create"
    @submit_value = 'Create Invoice'
    @page_title = "New Invoice — #{@client.name}"
    v :'invoices/create'
  end

  post '/:client_key/create' do
    client = find_client!(params[:client_key])
    data = gather_invoice_data(params[:invoice]).merge(services: submitted_services(params[:invoice]))
    data[:is_complete] = true
    invoice = client.create_invoice(data)
    create_invoice_pdf(invoice, current_business)
    flash[:success] = 'Invoice created successfully'
    redirect "/invoices/#{client.slug}"
  end

  get '/:client_key/:num/edit' do
    @client = find_client!(params[:client_key])
    @invoice = find_invoice!(@client, params[:num])
    @services = @invoice.services.empty? ? [Store::Service.new({})] : @invoice.services
    @action_url = "/invoices/#{@client.slug}/#{@invoice.num}"
    @submit_value = 'Update Invoice'
    @page_title = "Edit Invoice — #{@client.name}"
    v :'invoices/edit'
  end

  post '/:client_key/:num' do
    client = find_client!(params[:client_key])
    invoice = find_invoice!(client, params[:num])
    invoice.update(gather_invoice_data(params[:invoice]).merge(services: submitted_services(params[:invoice]), is_complete: true))
    create_invoice_pdf(invoice, current_business)
    flash[:success] = 'Invoice updated successfully'
    redirect "/invoices/#{client.slug}"
  end

  get '/:client_key/:num/approve' do
    client = find_client!(params[:client_key]); invoice = find_invoice!(client, params[:num])
    invoice.update(approved_on: Time.now) if invoice.approved_on.nil?
    flash[:success] = 'Invoice approved!'
    redirect "/invoices/#{client.slug}/#{invoice.num}"
  end

  get '/:client_key/:num/mark_sent' do
    client = find_client!(params[:client_key]); invoice = find_invoice!(client, params[:num])
    invoice.update(sent_at: Time.now) if invoice.sent_at.nil?
    flash[:success] = 'Invoice marked as sent!'
    redirect "/invoices/#{client.slug}/#{invoice.num}"
  end

  get '/:client_key/:num/paid' do
    client = find_client!(params[:client_key]); invoice = find_invoice!(client, params[:num])
    invoice.update(paid_at: Time.now) if invoice.paid_at.nil?
    flash[:success] = 'Invoice marked as paid!'
    redirect "/invoices/#{client.slug}/#{invoice.num}"
  end

  get '/:client_key/:num/delete' do
    client = find_client!(params[:client_key]); invoice = find_invoice!(client, params[:num])
    halt 403 unless invoice.deletable?
    invoice.soft_delete
    flash[:success] = 'Invoice deleted.'
    redirect "/invoices/#{client.slug}"
  end

  get '/:client_key/:num/pdf' do
    client = find_client!(params[:client_key]); invoice = find_invoice!(client, params[:num])
    halt 404 unless invoice.pdf_exists?
    send_file invoice.pdf_path, type: 'application/pdf', disposition: 'inline'
  end

  get '/:client_key/:num/preview' do
    @client = find_client!(params[:client_key])
    @invoice = find_invoice!(@client, params[:num])
    @company = current_business
    logo = current_business.resolve_logo
    @logo_url = logo ? logo[:web] : nil
    erb :'invoices/preview', layout: false
  end

  get '/:client_key/:num' do
    @client = find_client!(params[:client_key])
    @invoice = find_invoice!(@client, params[:num])
    @company = current_business
    @pdf_invoice_path = @invoice.pdf_exists? ? "/invoices/#{@client.slug}/#{@invoice.num}/pdf" : nil
    @page_title = "Invoice #{@client.prefix}-#{@invoice.num} — #{@client.name}"
    v :'invoices/view'
  end

  helpers do
    def create_invoice_pdf(invoice, business)
      Store::InvoicePdf.render(invoice, business, invoice.pdf_path)
    end
  end
end
