module Formattable
  def format_number(n, d)
    ("%.#{d}f" % n.to_f).to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
  end
end

class Client < Sequel::Model
  include Formattable
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  set_dataset(DB[:clients].where(deleted_at: nil))
  one_to_many :invoices

  def validate
    super
    validates_presence [:client_key, :client_prefix, :name, :contact, :email, :street, :city, :state, :zip]
  end

  def title=(name)
    self.name = name
    slug = name.to_s.downcase.gsub(/[^\w\s-]/, '').gsub(/[\s_]+/, '-').gsub(/-+/, '-').gsub(/\A-|-\z/, '')
    existing = self.class.first(client_key: slug)
    self.client_key = existing ? "#{slug}-#{rand(100)}" : slug
  end

  def soft_delete
    DB.transaction do
      invoices.each(&:soft_delete)
      update(deleted_at: Time.now)
    end
  end
end

class Invoice < Sequel::Model
  include Formattable
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  set_dataset(DB[:invoices].where(deleted_at: nil))
  many_to_one :client
  one_to_many :services

  def deletable?
    approved_on.nil?
  end

  def soft_delete
    update(deleted_at: Time.now)
  end

  def formatted_invoice_num(client_obj)
    if num && !num.empty?
      num
    elsif client_obj
      last = self.class.where(client_id: client_obj.id).order(Sequel.desc(:created_at)).first
      last ? "%03d" % (last.num.to_i + 1) : "001"
    else
      "001"
    end
  end

  def formatted_invoice_date
    invoice_date ? invoice_date.strftime("%m/%d/%Y") : Time.now.strftime("%m/%d/%Y")
  end

  def formatted_total_amount
    total_amount ? format_number(total_amount, 2) : "0.00"
  end

  def formatted_total_discount
    total_discount ? format_number(total_discount, 2) : "0.00"
  end

  def formatted_discount_percentage
    format_number((total_discount.to_f / total_amount.to_f) * 100, 1)
  end

  def formatted_discount_total_amount
    format_number(total_amount.to_f - total_discount.to_f, 2)
  end

  def formatted_final_amount
    format_number(total_amount.to_f - total_discount.to_f - amount_paid.to_f, 2)
  end

  def formatted_amount_paid
    amount_paid ? format_number(amount_paid, 2) : "0.00"
  end

  def formatted_terms
    terms || "Payable upon receipt"
  end

  def formatted_notes
    notes || "Thank you for your business"
  end

  def get_status
    if paid_at
      "paid"
    elsif sent_at && Time.now > sent_at + (15 * 24 * 3600)
      "late"
    elsif sent_at
      "sent"
    elsif approved_on
      "approved"
    else
      "draft"
    end
  end

  def editable?
    sent_at.nil?
  end

  def formatted_sent_date
    sent_at ? sent_at.strftime("%m/%d/%Y %H:%M:%S") : ""
  end

  def formatted_paid_date
    paid_at ? paid_at.strftime("%m/%d/%Y %H:%M:%S") : ""
  end
end

class Service < Sequel::Model
  include Formattable
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  many_to_one :invoice

  def formatted_service_date
    service_date ? service_date.strftime("%m/%d/%Y") : ""
  end

  def formatted_cost
    cost ? format_number(cost, 2) : ""
  end

  def formatted_line_total
    (cost && qty) ? format_number(qty * cost, 2) : ""
  end
end

class Timesheet < Sequel::Model
  include Formattable
  plugin :timestamps, update_on_create: true

  many_to_one :client
  many_to_one :invoice

  def formatted_service_date
    service_date ? service_date.strftime("%m/%d/%Y") : ""
  end

  def formatted_cost
    cost ? format_number(cost, 2) : ""
  end

  def formatted_line_total
    (cost && qty) ? format_number(qty.to_f * cost.to_f, 2) : ""
  end
end

class Company < Sequel::Model
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers

  def city_state_zip
    "#{city}, #{state} #{zip}"
  end
end

class Division < Sequel::Model
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers
  one_to_many :categories
end

class Category < Sequel::Model
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers
  many_to_one :division
  one_to_many :billing_codes
end

class BillingCode < Sequel::Model
  plugin :timestamps, update_on_create: true
  plugin :validation_helpers
  many_to_one :category
end
