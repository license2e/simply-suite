
class BaseModel 
  
  def format_number(n,d)
    return ("%.#{d}f" % n).to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
  end
end

class Client < BaseModel
  include DataMapper::Resource
  property :id, Serial
  
  property :client_key, String, :required => true, :unique_index => true, :length => 255
  property :client_prefix, String, :required => true, :length => 12
  property :name, String, :required => true
  property :contact, String, :required => true
  property :email, String, :required => true
  property :street, String, :required => true
  property :street2, String
  property :city, String, :required => true
  property :state, String, :required => true
  property :zip, String, :required => true
  
  property :created_at, DateTime
  property :created_on, Date
  property :updated_at, DateTime
  property :updated_on, Date

  has n, :invoices
  
  def title=(name)
    self.name = name
    self.client_key = self.name.gsub(/\s/, "-").gsub(/[^\w-]/, '').split("-").map {|name| name[0].chr.downcase }.join
    unique_client = self.class.first(:client_key => self.client_key)
    if !unique_client.nil? then
      self.client_key = "#{self.client_key}#{(0...2).map{ (0..19).to_a[rand(19)] }.join}"
    end
  end
end

class Invoice < BaseModel 
  include DataMapper::Resource
  property :id, Serial
  
  property :num, String
  property :invoice_date, DateTime
  property :total_amount, Float
  property :total_discount, Float
  property :amount_paid, Float
  property :is_complete, Boolean, :default  => false
  property :terms, Text
  property :notes, Text
  
  property :approved_on, DateTime
  property :sent_at, DateTime
  property :paid_at, DateTime
  property :created_at, DateTime
  property :created_on, Date
  property :updated_at, DateTime
  property :updated_on, Date
  
  belongs_to :client
  has n, :services
  
  def client_selected(client_id)
    if(self.client_id == client_id) then
      return true
    else
      return false
    end
  end
  
  @next_invoice_num = nil
  
  def formatted_invoice_num(client)
    if !self.num.nil? && !self.num.empty?
      @next_invoice_num = self.num
    elsif !@next_invoice_num.nil? && !@next_invoice_num.empty?
      @next_invoice_num = "%03d" % (@next_invoice_num.to_i + 1)
    elsif !client.nil?
      last_invoice = self.class.first(:client_id => client.id, :order => [:created_at.desc])
      if !last_invoice.nil? && last_invoice != [] then
        @next_invoice_num = "%03d" % (last_invoice.num.to_i + 1)
      else
        @next_invoice_num = "001"
      end
    else
      @next_invoice_num = "001"
    end  
    return @next_invoice_num
  end
  
  def formatted_invoice_date()
    return self.invoice_date.strftime("%m/%d/%Y") unless self.invoice_date.nil? #"%Y-%m-%d %H:%M:%S" 
    return DateTime.now.strftime("%m/%d/%Y")
  end
  
  def formatted_total_amount()
    return format_number(self.total_amount,2) unless self.total_amount.nil?
    return "0.00"
  end
  
  def formatted_total_discount()
    return format_number(self.total_discount,2) unless self.total_discount.nil?
    return "0.00"
  end
  
  def formatted_discount_percentage()
    percentage = (self.total_discount/self.total_amount)*100
    return format_number(percentage,1)
  end
  
  def formatted_discount_total_amount()
    discount_total_amount = (self.total_amount - self.total_discount)
    return format_number(discount_total_amount,2)
  end
  
  def formatted_final_amount()
    final_amount = (self.total_amount - self.total_discount - self.amount_paid)
    return format_number(final_amount,2)
  end
  
  def formatted_amount_paid()
    return format_number(self.amount_paid,2) unless self.amount_paid.nil?
    return "0.00"
  end
  
  def formatted_terms()
    return self.terms unless self.terms.nil?
    return "Payable upon receipt"
  end
  
  def formatted_notes()
    return self.notes unless self.notes.nil?
    return "Thank you for using EON Media Group, LLC"
  end
  
  def get_status()
    if !self.paid_at.nil? then
      return "paid"
    elsif self.paid_at.nil? && !self.sent_at.nil? && DateTime.parse(Time.now.to_s) > (self.sent_at+(15))
      return "late"
    elsif !self.sent_at.nil?
      return "sent"
    elsif !self.approved_on.nil?
      return "approved"
    else
      return "draft"
    end
  end
  
  def editable?
    if self.sent_at.nil? then
      return true
    end
    return false
  end
  
  def formatted_sent_date()
    return self.sent_at.strftime("%m/%d/%Y %H:%M:%S") unless self.sent_at.nil? #"%Y-%m-%d %H:%M:%S" 
    return ""
  end
  
  def formatted_paid_date()
    return self.paid_at.strftime("%m/%d/%Y %H:%M:%S") unless self.paid_at.nil? #"%Y-%m-%d %H:%M:%S" 
    return ""
  end
  
end

class Service < BaseModel 
  include DataMapper::Resource
  property :id, Serial
  
  property :item, String
  property :desc, String
  property :service_date, DateTime
  property :qty, Integer
  property :cost, Float
  
  property :created_at, DateTime
  property :created_on, Date
  property :updated_at, DateTime
  property :updated_on, Date
  
  belongs_to :invoice
  
  def formatted_service_date()
    return self.service_date.strftime("%m/%d/%Y") unless self.service_date.nil? #"%Y-%m-%d %H:%M:%S"
    return ""
  end
  
  def formatted_cost()
    return format_number(self.cost,2) unless self.cost.nil?
    return self.cost
  end

  def formatted_line_total()
    return format_number((self.qty * self.cost),2) unless self.cost.nil?
    return self.cost
  end
end

class Division
  include DataMapper::Resource
  property :id, Serial
  
  property :name, String
  
  property :created_at, DateTime
  property :created_on, Date
  property :updated_at, DateTime
  property :updated_on, Date
end

class Category
  include DataMapper::Resource
  property :id, Serial

  property :name, String
  belongs_to :division

  property :created_at, DateTime
  property :created_on, Date
  property :updated_at, DateTime
  property :updated_on, Date
end

class BillingCode
  include DataMapper::Resource
  property :id, Serial
  
  property :code, String
  property :desc, String
  property :notes, String
  property :rate, Float
  
  belongs_to :category
  
  property :created_at, DateTime
  property :created_on, Date
  property :updated_at, DateTime
  property :updated_on, Date
end

#Client.auto_migrate! #unless Client.storage_exists?
#Invoice.auto_migrate! #unless Invoice.storage_exists?
#Service.auto_migrate! #unless Service.storage_exists?
#DataMapper.auto_upgrade!