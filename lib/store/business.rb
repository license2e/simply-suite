module Store
  class Business
    FIELDS = %i[name contact email street city state zip].freeze
    DEFAULTS = { timesheet_period: 'monthly',
                 terms: 'Payable upon receipt',
                 notes: 'Thank you for your business' }.freeze

    attr_reader :slug

    def initialize(slug, data)
      @slug = slug
      @data = data
    end

    def self.create(attrs, logo_src = nil)
      slug = Store.slugify(attrs[:name], taken: all.map(&:slug))
      data = { slug: slug }
      FIELDS.each { |f| data[f] = attrs[f] }
      data[:defaults] = DEFAULTS.merge(attrs[:defaults] || {})
      data[:created_at] = Store.now_iso
      data[:updated_at] = data[:created_at]
      b = new(slug, data)
      Store.write_json(b.config_path, data)
      b.save_logo(logo_src) if logo_src && File.exist?(logo_src)
      b
    end

    def self.all
      Store.list_dirs(Store.data_root).filter_map { |s| find(s) }.sort_by { |b| b.name.to_s.downcase }
    end

    def self.find(slug)
      data = Store.read_json(File.join(Store.data_root, slug, 'config', 'settings.json'))
      data ? new(slug, data) : nil
    end

    FIELDS.each { |f| define_method(f) { @data[f] } }

    def defaults
      DEFAULTS.merge(@data[:defaults] || {})
    end

    def update(attrs)
      FIELDS.each { |f| @data[f] = attrs[f] if attrs.key?(f) }
      @data[:defaults] = defaults.merge(attrs[:defaults] || {}) if attrs.key?(:defaults)
      @data[:updated_at] = Store.now_iso
      Store.write_json(config_path, @data)
      self
    end

    def save_logo(src_path)
      dest = File.join(dir, 'config', 'logo.png')
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(src_path, dest)
      dest
    end

    def logo_file
      f = File.join(dir, 'config', 'logo.png')
      File.exist?(f) ? f : nil
    end

    def resolve_logo
      f = logo_file
      return nil unless f
      { local: f, web: "/businesses/logo?v=#{File.mtime(f).to_i}" }
    end

    def city_state_zip
      "#{city}, #{state} #{zip}"
    end

    def dir
      File.join(Store.data_root, slug)
    end

    def config_path
      File.join(dir, 'config', 'settings.json')
    end

    def clients_dir
      File.join(dir, 'clients')
    end

    def clients
      Store.list_dirs(clients_dir).reject { |s| s == 'archive' }
           .filter_map { |s| find_client(s) }
           .sort_by { |c| c.name.to_s.downcase }
    end

    def find_client(slug)
      data = Store.read_json(File.join(clients_dir, slug, 'client.json'))
      data ? Client.new(self, data) : nil
    end

    def create_client(attrs)
      slug = Store.slugify(attrs[:name], taken: Store.list_dirs(clients_dir) + %w[archive create])
      data = { slug: slug }
      Client::FIELDS.each { |f| data[f] = attrs[f] }
      data[:timesheet_period] = attrs[:timesheet_period]
      data[:created_at] = Store.now_iso
      data[:updated_at] = data[:created_at]
      c = Client.new(self, data)
      Store.write_json(File.join(c.dir, 'client.json'), data)
      c
    end

    def to_h
      @data.dup
    end
  end
end
