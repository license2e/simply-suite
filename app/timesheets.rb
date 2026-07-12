class Timesheets < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { require_business! }

  helpers Store::Formattable

  helpers do
    def parse_rows(entries)
      (entries || {}).values.map do |e|
        { id: e[:id], item: e[:item], desc: e[:desc],
          service_date: e[:service_date].to_s.empty? ? nil : (Date.strptime(e[:service_date], '%m/%d/%Y') rescue nil),
          qty: e[:qty], cost: e[:cost] }
      end
    end

    def fmt_date(v)
      return '' if v.to_s.empty?
      Date.parse(v.to_s).strftime('%m/%d/%Y')
    rescue ArgumentError
      ''
    end

    def fmt_money(v)
      return '' if v.nil? || v.to_s.empty?
      format_number(v, 2)   # shared with the store models via Store::Formattable
    end

    def fmt_line_total(entry)
      return '—' if entry[:qty].to_s.empty? || entry[:cost].to_s.empty?
      fmt_money(entry[:qty].to_f * entry[:cost].to_f)
    end
  end

  get '/' do
    @clients = current_business.clients
    @summaries = @clients.to_h { |c| [c.slug, c.timesheet_summary] }
    @page_title = 'Timesheets'
    v :'timesheets/index'
  end

  get '/:client_key' do
    @client = current_business.find_client(params[:client_key])
    halt 404 unless @client
    @period = @client.timesheet_period(params[:period])
    @entries = @period.entries
    @page_title = "Timesheets — #{@client.name}"
    v :'timesheets/show'
  end

  post '/:client_key' do
    client = current_business.find_client(params[:client_key])
    halt 404 unless client
    period = client.timesheet_period(params[:period])
    period.apply(rows: parse_rows(params[:entries]), deletes: params[:delete_entries] || [])
    flash[:success] = 'Timesheet saved.'
    redirect "/timesheets/#{client.slug}?period=#{period.key}"
  end

  post '/:client_key/invoice' do
    client = current_business.find_client(params[:client_key])
    halt 404 unless client
    period = client.timesheet_period(params[:period])
    invoice = period.create_invoice
    if invoice
      flash[:success] = "Draft invoice #{client.prefix}-#{invoice.num} created."
      redirect "/invoices/#{client.slug}/#{invoice.num}/edit"
    else
      flash[:error] = 'No un-invoiced entries in this period.'
      redirect "/timesheets/#{client.slug}?period=#{period.key}"
    end
  end
end
