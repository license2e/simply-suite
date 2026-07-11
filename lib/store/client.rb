# lib/store/client.rb
module Store
  class Client
    FIELDS = %i[prefix name contact email street street2 city state zip].freeze

    attr_reader :business, :data

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

    def update(attrs)
      FIELDS.each { |f| @data[f] = attrs[f] if attrs.key?(f) }
      @data[:timesheet_period] = attrs[:timesheet_period] if attrs.key?(:timesheet_period)
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

    def to_h = @data
  end
end
