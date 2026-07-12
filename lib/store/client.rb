# lib/store/client.rb
module Store
  class Client
    FIELDS = %i[prefix name contact email street street2 city state zip].freeze

    attr_reader :business

    def initialize(business, data)
      @business = business
      @data = data
    end

    def slug = @data[:slug]

    FIELDS.each { |f| define_method(f) { @data[f] } }

    def timesheet_period_override
      v = @data[:timesheet_period]
      v.nil? || v.to_s.empty? ? nil : v
    end

    def resolved_timesheet_period
      timesheet_period_override || business.defaults[:timesheet_period]
    end

    # Per-client default rate used to pre-fill new timesheet rows (stored as a
    # sanitized string, e.g. "125" / "125.50"; nil when unset).
    def default_rate
      v = @data[:default_rate]
      v.nil? || v.to_s.empty? ? nil : v.to_s
    end

    def update(attrs)
      FIELDS.each { |f| @data[f] = attrs[f] if attrs.key?(f) }
      @data[:timesheet_period] = attrs[:timesheet_period] if attrs.key?(:timesheet_period)
      if attrs.key?(:default_rate)
        raw = attrs[:default_rate].to_s.gsub(/[^\d.]/, '')
        @data[:default_rate] = raw.empty? ? nil : raw
      end
      @data[:updated_at] = Store.now_iso
      Store.write_json(File.join(dir, 'client.json'), @data)
      self
    end

    def soft_delete
      archive = File.join(business.clients_dir, 'archive', slug)
      FileUtils.rm_rf(archive)
      Store.move(dir, archive)
    end

    def dir
      File.join(business.clients_dir, slug)
    end

    def invoices_dir
      File.join(dir, 'invoices')
    end

    def invoices
      Store.list_files(invoices_dir, '.json')
           .filter_map { |f| find_invoice(File.basename(f, '.json')) }
           .sort_by { |i| -i.num.to_i }
    end

    def find_invoice(num)
      data = Store.read_json(File.join(invoices_dir, "#{num}.json"))
      data ? Invoice.new(self, data) : nil
    end

    def next_num
      nums = (Store.list_files(invoices_dir, '.json') +
              Store.list_files(File.join(invoices_dir, 'archive'), '.json'))
             .map { |f| File.basename(f, '.json') }
      return '001' if nums.empty?
      width = nums.map(&:length).max            # pad to widest existing (no forced min once numbers exist)
      max   = nums.map(&:to_i).max
      format("%0#{width}d", max + 1)
    end

    def create_invoice(attrs)
      num = attrs[:num].to_s.empty? ? next_num : attrs[:num].to_s
      if File.exist?(File.join(invoices_dir, "#{num}.json"))
        raise Store::DuplicateInvoiceNumber, "Invoice #{num} already exists"
      end
      inv = Invoice.new(self, Invoice.blank_data(num))
      inv.update(attrs.merge(num: num))
      inv
    end

    def timesheets_dir
      File.join(dir, 'timesheets')
    end

    def timesheet_period(key = nil)
      key ||= TimesheetPeriod.key_for(Date.today, resolved_timesheet_period)
      TimesheetPeriod.new(self, key)
    end

    def timesheet_summary
      total = 0
      uninvoiced = 0
      Store.list_files(timesheets_dir, '.json').each do |f|
        data = Store.read_json(File.join(timesheets_dir, f)) || {}
        (data[:entries] || []).each do |e|
          total += 1
          uninvoiced += 1 unless e[:invoiced]
        end
      end
      { total: total, uninvoiced: uninvoiced }
    end

    def to_h = @data.dup
  end
end
