class Timesheets < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { authorize! }

  get '/' do
    @clients = Client.order(:name).all
    @page_title = 'Timesheets'
    v :'timesheets/index'
  end

  get '/:client_key' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client
    @entries = Timesheet.where(client_id: @client.id).order(:service_date, :id).all
    @page_title = "Timesheets — #{@client.name}"
    v :'timesheets/show'
  end

  post '/:client_key' do
    @client = Client.first(client_key: params[:client_key])
    halt 404 unless @client

    (params[:entries] || {}).each do |_key, e|
      next if e[:item].to_s.empty? && e[:desc].to_s.empty?
      svc_date = e[:service_date].to_s.empty? ? nil : (DateTime.strptime(e[:service_date], "%m/%d/%Y") rescue nil)
      attrs = {
        item:         e[:item].to_s.empty? ? nil : e[:item],
        desc:         e[:desc].to_s.empty? ? nil : e[:desc],
        service_date: svc_date,
        qty:          e[:qty].to_s.empty? ? nil : e[:qty].to_f,
        cost:         e[:cost].to_s.empty? ? nil : e[:cost].to_f
      }
      if e[:id] && !e[:id].empty?
        entry = Timesheet.first(id: e[:id].to_i, client_id: @client.id)
        entry.update(attrs) if entry && !entry.invoiced
      else
        Timesheet.create(attrs.merge(client_id: @client.id, invoiced: false))
      end
    end

    (params[:delete_entries] || []).each do |id|
      entry = Timesheet.first(id: id.to_i, client_id: @client.id)
      entry.destroy if entry && !entry.invoiced
    end

    flash[:success] = "Timesheet saved."
    redirect url("/#{@client.client_key}")
  end
end
