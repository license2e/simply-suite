module Store
  class Service
    include Formattable

    attr_reader :item, :desc, :service_date, :qty, :cost

    def initialize(h)
      @item = blank_to_nil(h[:item])
      @desc = blank_to_nil(h[:desc])
      @service_date = parse_date(h[:service_date])
      @qty  = h[:qty].nil? || h[:qty].to_s.empty? ? nil : h[:qty].to_f
      @cost = h[:cost].nil? || h[:cost].to_s.empty? ? nil : h[:cost].to_f
    end

    def formatted_service_date
      service_date ? service_date.strftime('%m/%d/%Y') : ''
    end

    def formatted_cost
      cost ? format_number(cost, 2) : ''
    end

    def formatted_line_total
      (cost && qty) ? format_number(qty * cost, 2) : ''
    end

    def to_h
      { item: item, desc: desc,
        service_date: service_date&.strftime('%Y-%m-%d'),
        qty: qty, cost: cost }
    end

    private

    def blank_to_nil(v)
      v.nil? || v.to_s.empty? ? nil : v
    end

    def parse_date(v)
      return v if v.is_a?(Date)
      return nil if v.nil? || v.to_s.strip.empty?
      Date.parse(v.to_s)
    rescue ArgumentError
      nil
    end
  end
end
