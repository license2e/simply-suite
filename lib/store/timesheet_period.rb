# lib/store/timesheet_period.rb
module Store
  class TimesheetPeriod
    attr_reader :client, :key

    def initialize(client, key)
      @client = client
      @key = key
    end

    def self.key_for(date, granularity)
      d = date.is_a?(Date) ? date : Date.parse(date.to_s)
      case granularity
      when 'daily'     then d.strftime('%Y-%m-%d')
      when 'weekly'    then format('%d-W%02d', d.cwyear, d.cweek)
      when 'quarterly' then "#{d.year}-Q#{((d.month - 1) / 3) + 1}"
      else                  d.strftime('%Y-%m') # monthly default
      end
    end

    def granularity
      client.resolved_timesheet_period
    end

    def path
      File.join(client.timesheets_dir, "#{key}.json")
    end

    def load
      Store.read_json(path) || { period: key, granularity: granularity, entries: [] }
    end

    def entries
      load[:entries] || []
    end

    def apply(rows:, deletes:)
      data = load
      list = data[:entries] || []
      by_id = list.each_with_object({}) { |e, h| h[e[:id]] = e }
      deletes = Array(deletes).map(&:to_s)

      # Removals -> archive (skip invoiced)
      removed = []
      deletes.each do |id|
        e = by_id[id]
        next if e.nil? || e[:invoiced]
        list.delete(e)
        removed << e
      end
      archive_entries(removed) unless removed.empty?

      # Upserts (skip invoiced existing)
      moved_out = []
      Array(rows).each do |row|
        next if row[:item].to_s.empty? && row[:desc].to_s.empty?
        svc = Service.new(row).to_h
        target_key = svc[:service_date] ? self.class.key_for(svc[:service_date], granularity) : key
        id = row[:id].to_s
        if !id.empty? && by_id[id]
          existing = by_id[id]
          next if existing[:invoiced]
          existing.merge!(svc.merge(updated_at: Store.now_iso))
          if target_key != key
            list.delete(existing)
            moved_out << existing
          end
        else
          entry = svc.merge(id: SecureRandom.hex(3), invoiced: false, invoice_num: nil,
                            created_at: Store.now_iso, updated_at: Store.now_iso)
          if target_key == key
            list << entry
          else
            add_to_period(target_key, entry)
          end
        end
      end
      moved_out.each { |e| add_to_period(self.class.key_for(e[:service_date], granularity), e) }

      data[:entries] = list
      data[:period] = key
      data[:granularity] = granularity
      Store.write_json(path, data)
    end

    def prev_key = shift(-1)
    def next_key = shift(1)

    def create_invoice
      data = load
      pending = (data[:entries] || []).reject { |e| e[:invoiced] }
      return nil if pending.empty?

      total = pending.sum { |e| e[:qty].to_f * e[:cost].to_f }
      inv = client.create_invoice(
        invoice_date: Date.today.strftime('%Y-%m-%d'),
        total_amount: total, total_discount: 0.0, amount_paid: 0.0,
        services: pending.map { |e| { item: e[:item], desc: e[:desc], service_date: e[:service_date], qty: e[:qty], cost: e[:cost] } }
      )
      pending.each { |e| e[:invoiced] = true; e[:invoice_num] = inv.num; e[:updated_at] = Store.now_iso }
      Store.write_json(path, data)
      inv
    end

    private

    def shift(n)
      case granularity
      when 'daily'     then (Date.parse(key) + n).strftime('%Y-%m-%d')
      when 'weekly'    then y, w = key.split('-W'); self.class.key_for(Date.commercial(y.to_i, w.to_i, 1) + (7 * n), 'weekly')
      when 'quarterly' then y, q = key.split('-Q'); m = ((q.to_i - 1) * 3) + 1; self.class.key_for(Date.new(y.to_i, m, 1) >> (3 * n), 'quarterly')
      else y, m = key.split('-'); self.class.key_for(Date.new(y.to_i, m.to_i, 1) >> n, 'monthly')
      end
    end

    def add_to_period(target_key, entry)
      tp = TimesheetPeriod.new(client, target_key)
      data = tp.load
      (data[:entries] ||= []) << entry
      Store.write_json(tp.path, data)
    end

    def archive_entries(entries)
      apath = File.join(client.timesheets_dir, 'archive', "#{key}.json")
      data = Store.read_json(apath) || { period: key, entries: [] }
      (data[:entries] ||= []).concat(entries)
      Store.write_json(apath, data)
    end
  end
end
