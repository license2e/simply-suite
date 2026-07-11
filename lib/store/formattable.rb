module Store
  module Formattable
    def format_number(n, d)
      ('%.*f' % [d, n.to_f]).gsub(/(\d)(?=(\d\d\d)+(?!\d))/, '\\1,')
    end
  end
end
