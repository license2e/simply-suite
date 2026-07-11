# lib/store/invoice.rb
module Store
  class Invoice
    include Formattable

    SCALARS = %i[num invoice_date total_amount total_discount amount_paid
                 is_complete terms notes approved_on sent_at paid_at].freeze

    attr_reader :client, :data

    def initialize(client, data)
      @client = client
      @data = data
    end

    def self.blank_data(num)
      { num: num, invoice_date: nil, total_amount: 0.0, total_discount: 0.0,
        amount_paid: 0.0, is_complete: false, terms: nil, notes: nil,
        approved_on: nil, sent_at: nil, paid_at: nil, services: [],
        created_at: Store.now_iso, updated_at: Store.now_iso }
    end

    def num = @data[:num]
    def total_amount = @data[:total_amount]
    def total_discount = @data[:total_discount]
    def amount_paid = @data[:amount_paid]
    def is_complete = @data[:is_complete]
    def terms = @data[:terms]
    def notes = @data[:notes]

    def invoice_date = parse_date(@data[:invoice_date])
    def approved_on  = parse_time(@data[:approved_on])
    def sent_at      = parse_time(@data[:sent_at])
    def paid_at      = parse_time(@data[:paid_at])

    def services
      (@data[:services] || []).map { |h| Service.new(h) }
    end

    def update(attrs)
      SCALARS.each do |f|
        next unless attrs.key?(f)
        @data[f] = normalize(f, attrs[f])
      end
      if attrs.key?(:services)
        @data[:services] = Array(attrs[:services])
          .map { |row| Service.new(row).to_h }
          .reject { |h| h[:item].nil? && h[:desc].nil? }
      end
      @data[:updated_at] = Store.now_iso
      Store.write_json(json_path, @data)
      self
    end

    def soft_delete
      unbill_timesheets
      Store.move(json_path, File.join(client.invoices_dir, 'archive', "#{num}.json"))
      Store.move(pdf_path, File.join(client.invoices_dir, 'archive', pdf_filename)) if pdf_exists?
    end

    def unbill_timesheets
      dir = client.timesheets_dir
      Store.list_files(dir, '.json').each do |f|
        path = File.join(dir, f)
        data = Store.read_json(path)
        changed = false
        (data[:entries] || []).each do |e|
          next unless e[:invoice_num] == num
          e[:invoiced] = false
          e[:invoice_num] = nil
          changed = true
        end
        Store.write_json(path, data) if changed
      end
    end

    # ---- formatting / status (ported from models/models.rb) ----
    def formatted_invoice_num
      num && !num.to_s.empty? ? num : '001'
    end

    def formatted_invoice_date
      (invoice_date || Date.today).strftime('%m/%d/%Y')
    end

    def formatted_total_amount   = format_number(total_amount || 0, 2)
    def formatted_total_discount = format_number(total_discount || 0, 2)

    def formatted_discount_percentage
      format_number((total_discount.to_f / total_amount.to_f) * 100, 1)
    end

    def formatted_discount_total_amount
      format_number(total_amount.to_f - total_discount.to_f, 2)
    end

    def formatted_final_amount
      format_number(total_amount.to_f - total_discount.to_f - amount_paid.to_f, 2)
    end

    def formatted_amount_paid = format_number(amount_paid || 0, 2)
    def formatted_terms = terms || 'Payable upon receipt'
    def formatted_notes = notes || 'Thank you for your business'
    def formatted_sent_date = sent_at ? sent_at.strftime('%m/%d/%Y %H:%M:%S') : ''
    def formatted_paid_date = paid_at ? paid_at.strftime('%m/%d/%Y %H:%M:%S') : ''

    def get_status
      if paid_at then 'paid'
      elsif sent_at && Time.now > sent_at + (15 * 24 * 3600) then 'late'
      elsif sent_at then 'sent'
      elsif approved_on then 'approved'
      else 'draft'
      end
    end

    def deletable? = approved_on.nil?
    def editable?  = sent_at.nil?

    def pdf_filename = "#{client.prefix}-#{num}.pdf"
    def pdf_path = File.join(client.invoices_dir, pdf_filename)
    def pdf_exists? = File.exist?(pdf_path)
    def json_path = File.join(client.invoices_dir, "#{num}.json")

    private

    def normalize(field, v)
      case field
      when :invoice_date then v.is_a?(Date) ? v.strftime('%Y-%m-%d') : (v.to_s.empty? ? nil : v.to_s)
      when :approved_on, :sent_at, :paid_at
        return nil if v.nil?
        v.is_a?(Time) ? v.utc.strftime('%Y-%m-%dT%H:%M:%SZ') : v.to_s
      when :total_amount, :total_discount, :amount_paid then v.to_f
      else v
      end
    end

    def parse_date(v)
      return v if v.is_a?(Date)
      v && !v.to_s.empty? ? Date.parse(v.to_s) : nil
    rescue ArgumentError
      nil
    end

    def parse_time(v)
      return v if v.is_a?(Time)
      v && !v.to_s.empty? ? Time.parse(v.to_s) : nil
    rescue ArgumentError
      nil
    end
  end
end
