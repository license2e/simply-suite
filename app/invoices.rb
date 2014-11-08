require 'prawn'

class Invoices < SimplyBase
  set :layout_default, :'admin/layout-default'
  title << 'Admin'
  stylesheets << 'invoices.css'
  
  configure do
    require './models/user'
    require './models/models'
    DataMapper.finalize
  end
  
  before do
    authorize!
  end
  
  get '/:client_key?' do
    @invoices = nil
    @client = nil
    if params[:client_key] != nil then
      @client = Client.first(:client_key => params[:client_key])
      @invoices = Invoice.all(:client_id => @client.id, :order => [:num.desc], :limit => 20)
      title << "Invoices for #{@client.name}"
      v :"invoices/list"
    else
      redirect '/clients'
    end
  end
  
  get '/create/:client_key' do
    @client = Client.first(:client_key => params[:client_key])
    @invoice = Invoice.new
    @invoice.services << Service.new
    @services = @invoice.services
    @action_url = url("/create/#{@client.client_key}")
    @submit_value = "Create New Invoice"
  
    title << "Create Invoice for #{@client.name}"
    javascripts << 'jquery.example.min.js'
    javascripts << 'invoices.js'
    v :"invoices/create"
  end
  
  get '/edit/:id' do
    @invoice = Invoice.get(params[:id])
    #puts @invoice.inspect
    client = Client.get(@invoice.client_id)
    @invoice.client = client
    @services = @invoice.services
    if @services == [] then
      @services << Service.new()
    end
    @action_url = url("/update/#{@invoice.id}")
    @submit_value = "Update Invoice"
    
    title << "Update Invoice for: #{@invoice.client.name}"
    javascripts << 'jquery.example.min.js'
    javascripts << 'invoices.js'
    v :"invoices/edit"
  end
  
  post '/create/:client_key' do
    invoiceData = params[:invoice]
    puts invoiceData.inspect
    if params[:client_key] == nil then
      flash[:error] = "Please select a client"
      redirect url('/')
    end
    client = Client.first(:client_key => params[:client_key])
    invoice = Invoice.new(gather_invoice_data(invoiceData))
    invoice.client = client
    begin
      # save the invoice
      invoice.save      
    rescue DataMapper::SaveFailureError => e
      raise "#{e.to_s} -- validation(s): #{invoice.errors.values.join(', ')}"
    rescue StandardError => e
      raise "#{e.to_s}"
    end
    # process the invoice services
    process_invoice_services(invoiceData, invoice)
    # validate the invoice
    if validate_invoice(invoice) then
      logopath = '/css/images/logo.png'
      public_path = settings.public_path
      create_invoice_pdf(public_path, invoice, logopath)
      flash[:success] = "Successfully added the invoice"
      redirect url("/#{invoice.client.client_key}")
    end
    flash[:error] = "Please enter required data"
    redirect url("/edit/#{invoice.id.to_s}")
  end
  
  post '/update/:id' do
    invoiceData = params[:invoice]
    invoice = Invoice.get(params[:id])
    
    begin
      # update the invoice
      invoice.update(gather_invoice_data(invoiceData))
    rescue DataMapper::SaveFailureError => e
      raise "#{e.to_s} -- validation(s): #{invoice.errors.values.join(', ')}"
    rescue StandardError => e
      raise "#{e.to_s}"
    end
    # process the invoice services
    process_invoice_services(invoiceData, invoice)
    # validate the invoice
    if validate_invoice(invoice) then    
      logopath = '/css/images/logo.png'
      public_path = settings.public_path
      create_invoice_pdf(public_path, invoice, logopath)
      flash[:success] = "Successfully updated the invoice"
      redirect url("/#{invoice.client.client_key}")
    end    
    flash[:error] = "Please enter required data"
    redirect url("/edit/#{invoice.id.to_s}")
  end
  
  get '/view/:id' do
    
    @invoice = Invoice.get(params[:id])
    public_path = settings.public_path
    @logopath = '/css/images/logo.png'
    pdf_invoice_paths = get_invoice_pdf_path(public_path, @invoice)
    @pdf_invoice_path = pdf_invoice_paths[:web]
    
    title << "Invoice: #{@invoice.num} - #{@invoice.client.name}"
    
    v :"invoices/view"
  end
  
  get '/approve/:id' do
    @invoice = Invoice.get(params[:id])
    if @invoice.approved_on.nil? then
      @invoice.update({:approved_on => Time.now})
    end
    flash[:success] = "The invoice has been approved!"
    redirect url("/view/#{@invoice.id}")
  end
  
  get '/send/:id' do
    require 'app/mailman'
    @invoice = Invoice.get(params[:id])
    email_options = {}
    email_options[:invoice] = @invoice
    email_options[:html_body] = haml :"invoices/html_email"
    email_options[:text_body] = haml :"invoices/text_email"
    email_options[:public_path] = settings.public_path
        
    Mailman.invoice(email_options).deliver
    
    if @invoice.sent_at.nil? then
      @invoice.update({:sent_at => Time.now})
    end
    flash[:success] = "The invoice has been sent successfully!"
    redirect url("/view/#{@invoice.id}")
  end
  
  get '/paid/:id' do
    @invoice = Invoice.get(params[:id])
    if @invoice.paid_at.nil? then
      begin
        @invoice.update({:paid_at => Time.now})
      rescue DataMapper::SaveFailureError => e
        raise "#{e.to_s} -- validation(s): #{@invoice.errors.values.join(', ')}"
      rescue StandardError => e
        raise "#{e.to_s}"
      end
    end
    flash[:success] = "The invoice has been marked paid!"
    redirect url("/view/#{@invoice.id}")
  end
  
  helpers do
    
    def process_invoice_services(invoiceData, invoice)
      
      invoiceData[:services].each do |service_item|
        if service_item[1][:service_id] != "" then
          serv = Service.get(service_item[1][:service_id]);
          begin
            serv.update({
              :item => service_item[1][:item].empty? ? nil : service_item[1][:item],
              :desc => service_item[1][:desc].empty? ? nil : service_item[1][:desc],
              :service_date => service_item[1][:service_date].empty? ? nil : service_item[1][:service_date],
              :qty => service_item[1][:qty].empty? ? nil : service_item[1][:qty],
              :cost => service_item[1][:cost].empty? ? nil : service_item[1][:cost],
            })
          rescue DataMapper::SaveFailureError => e
            raise "#{e.to_s} -- validation(s): #{serv.errors.values.join(', ')}"
          rescue StandardError => e
            raise "#{e.to_s}"
          end
        else
          serv = Service.new({
            :item => service_item[1][:item].empty? ? nil : service_item[1][:item],
            :desc => service_item[1][:desc].empty? ? nil : service_item[1][:desc],
            :service_date => service_item[1][:service_date].empty? ? nil : service_item[1][:service_date],
            :qty => service_item[1][:qty].empty? ? nil : service_item[1][:qty],
            :cost => service_item[1][:cost].empty? ? nil : service_item[1][:cost].gsub("[\d\.]",""),
          });
          serv.invoice = invoice
          begin
            serv.save
          rescue DataMapper::SaveFailureError => e
            raise "#{e.to_s} -- validation(s): #{serv.errors.values.join(', ')}"
          rescue StandardError => e
            raise "#{e.to_s}"
          end
        end
      end
      
      if !invoiceData[:delete_services].nil? then
        invoiceData[:delete_services].each do |delete_item_id|
          delete_item = Service.get(delete_item_id)
          delete_item.destroy
        end
      end
      
    end
    
    def gather_invoice_data(invoiceData)
      return {
        :num => invoiceData[:num].empty? ? nil : invoiceData[:num],
        :invoice_date => invoiceData[:invoice_date].empty? ? nil : DateTime.strptime(invoiceData[:invoice_date], "%m/%d/%Y"),
        :total_amount => invoiceData[:total_amount].empty? ? 0.0 : invoiceData[:total_amount].gsub("[\d\.]",""),
        :total_discount => invoiceData[:total_discount].empty? ? 0.0 : invoiceData[:total_discount].gsub("[\d\.]",""),
        :amount_paid => invoiceData[:amount_paid].empty? ? 0.0 : invoiceData[:amount_paid].gsub("[\d\.]",""),
        :terms => invoiceData[:terms].empty? ? "" : invoiceData[:terms],
        :notes => invoiceData[:notes].empty? ? "" : invoiceData[:notes],
        :approved_on => nil,
      }
    end
    
    def validate_invoice(invoice)
      if invoice.client_id != nil && invoice.total_amount != nil && invoice.num != nil && invoice.services != [] then
        invoice.update({
          :is_complete => true
        })
        return true
      end
      return false
    end
    
    def get_invoice_pdf_path(public_path, invoice)
      invoice_web_path = "/pdfs/#{invoice.client.client_key}"
      invoice_local_path = File.join(public_path, invoice_web_path)
      FileUtils.mkdir_p(invoice_local_path)
      invoice_file_name = "#{invoice.client.client_prefix}-#{invoice.num}.pdf"
      invoice_local_file = File.join(invoice_local_path, invoice_file_name)
      invoice_web_file = File.join(invoice_web_path, invoice_file_name)
      
      return {:local => invoice_local_file, :web => invoice_web_file, :web_path => invoice_web_path}
    end
    
    def create_invoice_pdf(public_path, invoice, logopath)
      #require 'net/scp'
      
      invoice_file_paths = get_invoice_pdf_path(public_path, invoice)
      invoice_local_file = invoice_file_paths[:local]
      
      #if !File.exists?(invoice_local_file) then
        
        Prawn::Document.generate(invoice_local_file) do |pdf|
          logopath_local = File.join(public_path,logopath)
          initial_y = pdf.cursor
          initialmove_y = 25
          address_x = 35
          invoice_header_x = 325
          page_number_x = 485
          lineheight_y = 12
          font_size = 9
          font_width_assumed = 5

          pdf.move_down initialmove_y

          # Add the font style and size
          pdf.font "Helvetica"
          pdf.font_size font_size

          # start with your address
          pdf.text_box "EON Media Group, LLC", :at => [address_x,  pdf.cursor]
          pdf.move_down lineheight_y
          pdf.text_box "1800 Camden Rd. Suite 107/123", :at => [address_x,  pdf.cursor]
          pdf.move_down lineheight_y
          pdf.text_box "Charlotte, NC 28203", :at => [address_x,  pdf.cursor]
          pdf.move_down lineheight_y
          
          last_measured_y = pdf.cursor
          pdf.move_cursor_to pdf.bounds.height

          pdf.image logopath_local, :width => 125, :position => :right

          pdf.move_cursor_to last_measured_y

          # client address
          pdf.move_down 85
          last_measured_y = pdf.cursor

          pdf.text_box "#{invoice.client.name}", :at => [address_x,  pdf.cursor]
          pdf.move_down lineheight_y
          pdf.text_box "#{invoice.client.contact}", :at => [address_x,  pdf.cursor]
          pdf.move_down lineheight_y
          pdf.text_box "#{invoice.client.street} #{invoice.client.street2}", :at => [address_x,  pdf.cursor]
          pdf.move_down lineheight_y
          pdf.text_box "#{invoice.client.city}, #{invoice.client.state} #{invoice.client.zip}", :at => [address_x,  pdf.cursor]

          pdf.move_cursor_to last_measured_y

          invoice_header_data = [ 
            ["Invoice #", "#{invoice.client.client_prefix}-#{invoice.num}"],
            ["Invoice Date", "#{invoice.formatted_invoice_date()}"],
            ["Balance", "$#{invoice.formatted_final_amount()} USD"]
          ]

          pdf.table(invoice_header_data, :position => invoice_header_x, :width => 215) do
            style(row(0..1).columns(0..1), :padding => [2, 5, 2, 5], :borders => [])
            style(row(2), :background_color => 'e9e9e9', :border_color => 'dddddd', :font_style => :bold)
            style(column(1), :align => :right)
            style(row(2).columns(0), :borders => [:top, :left, :bottom])
            style(row(2).columns(1), :borders => [:top, :right, :bottom])
          end

          pdf.move_down 45

          invoice_services_data = []
          invoice_services_data << ["Item", "Description", "Unit Cost", "Quantity", "Line Total"]
          invoice.services.each do |service|
            invoice_services_data << ["#{service.item}", "#{service.desc}", "$#{service.formatted_cost()}", "#{service.qty}", "$#{service.formatted_line_total()}"]
          end
          invoice_services_data << [" ", " ", " ", " ", " "]

          pdf.table(invoice_services_data, :width => pdf.bounds.width) do
            style(row(1..-1).columns(0..-1), :padding => [4, 5, 4, 5], :borders => [:bottom], :border_color => 'dddddd')
            style(row(0), :background_color => 'e9e9e9', :border_color => 'dddddd', :font_style => :bold)
            style(row(0).columns(0..-1), :borders => [:top, :bottom])
            style(row(0).columns(0), :borders => [:top, :left, :bottom])
            style(row(0).columns(-1), :borders => [:top, :right, :bottom])
            style(row(-1), :border_width => 2)
            style(column(2..-1), :align => :right)
            style(columns(0), :width => 75)
            style(columns(1), :width => 275)
          end

          pdf.move_down 1

          invoice_services_totals_data = []
          
          if invoice.total_discount > 0.0 then
            invoice_services_totals_data << ["Sub Total", "$#{invoice.formatted_total_amount()}"]
            invoice_services_totals_data << ["Discount -#{invoice.formatted_discount_percentage()}%", "$#{invoice.formatted_total_discount()}"]
            invoice_services_totals_data << ["Invoice Total", "$#{invoice.formatted_discount_total_amount()}"]
          else
            invoice_services_totals_data << ["Invoice Total", "$#{invoice.formatted_total_amount()}"]
          end  
          invoice_services_totals_data << ["Amount Paid", "-$#{invoice.formatted_amount_paid()}"]
          invoice_services_totals_data << ["Balance", "$#{invoice.formatted_final_amount()} USD"]


          pdf.table(invoice_services_totals_data, :position => invoice_header_x, :width => 215) do
          
            style(row(0), :font_style => :bold)
            style(column(1), :align => :right)
            
            if invoice.total_discount > 0.0 then
              style(row(0..3).columns(0..3), :padding => [2, 5, 2, 5], :borders => [])
              style(row(2), :font_style => :bold, :border_color => 'dddddd', :borders => [:top])
              style(row(4), :background_color => 'e9e9e9', :border_color => 'dddddd', :font_style => :bold)
              style(row(4).columns(0), :borders => [:top, :left, :bottom])
              style(row(4).columns(1), :borders => [:top, :right, :bottom])
            else
              style(row(0..1).columns(0..1), :padding => [2, 5, 2, 5], :borders => [])
              style(row(2), :background_color => 'e9e9e9', :border_color => 'dddddd', :font_style => :bold)
              style(row(2).columns(0), :borders => [:top, :left, :bottom])
              style(row(2).columns(1), :borders => [:top, :right, :bottom])
            end
          end

          pdf.move_down 25

          invoice_terms_data = [ 
            ["Terms"],
            ["#{invoice.terms}"]
          ]

          pdf.table(invoice_terms_data, :width => 275) do
            style(row(0..-1).columns(0..-1), :padding => [1, 0, 1, 0], :borders => [])
            style(row(0).columns(0), :font_style => :bold)
          end

          pdf.move_down 15

          invoice_notes_data = [ 
            ["Notes"],
            ["#{invoice.notes}"]
          ]

          pdf.table(invoice_notes_data, :width => 275) do
            style(row(0..-1).columns(0..-1), :padding => [1, 0, 1, 0], :borders => [])
            style(row(0).columns(0), :font_style => :bold)
          end
          
          # company name, address, and contact
          #pdf.text_box "EON Media Group, 1800 Camden Rd. Suite 107/123, Charlotte, NC 28203", :at => [address_x,  10]
          
          page_num = "page 1 of 1"
          # page number
          pdf.text_box page_num, :at => [(pdf.bounds.width-(page_num.length*font_width_assumed)),  10]

        end # Prawn::Document.generate(invoice_local_file) do |pdf|
      #end # end if !File.exists?(invoice_local_file) then
      # return the invoice_file web path
      
=begin
      # move the files to the static site
      if File.exists?(invoice_file_paths[:local]) then
        remote_file_path = "/home/shindy/static.eonmediagroup.com/public#{invoice_file_paths[:web_path]}"
        remote_file = "/home/shindy/static.eonmediagroup.com/public#{invoice_file_paths[:web]}"
        Net::SSH.start("shindyapin.com", "shindy", :password => 'i#$nID$N') do |ssh|
          ssh.exec!("mkdir -p #{remote_file_path}")
        end
        Net::SCP.upload!("shindyapin.com", "shindy", invoice_file_paths[:local], remote_file, :password => 'i#$nID$N')
      else
        puts ">>> #{invoice_file_paths[:local]} does not exist!"
      end
=end
      
      return invoice_file_paths[:web]
    end
    
  end
  #end of helpers
end
#end of Invoices app class
