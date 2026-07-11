# JSON File Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Simply Suite's Sequel/SQLite database with a JSON-file data store, add multi-business support with onboarding + a session business switcher, per-client period-bucketed timesheets with roll-into-invoice, co-located PDFs served via an app route, and drop authentication and email.

**Architecture:** A new `lib/store/` layer of plain Ruby objects (`Store`, `Business`, `Client`, `Invoice`, `Service`, `TimesheetPeriod`) reads/writes JSON under a gitignored `data/<business>/…` tree, with atomic writes. Sinatra controllers resolve the active business from the session and call these objects instead of Sequel models. A one-time export script migrates the existing SQLite DB, after which all DB/auth/email code is deleted.

**Tech Stack:** Ruby 3.3 · Sinatra 4 (modular) · Prawn + prawn-table (PDF) · ERB · Tailwind · RSpec + rack-test. Removed: Sequel, sqlite3, mysql2, mail, bcrypt.

**Spec:** `docs/superpowers/specs/2026-07-11-json-file-storage-design.md` (read it first).

## Global Constraints

- Ruby 3.3; no database, ORM, or SQL after Task 13. Standard library only for the store (`json`, `fileutils`, `securerandom`, `date`).
- Data root: `ENV['DATA_DIR']` or `<repo>/data`. It is `.gitignored`.
- Directory names are **slugs**; slugs are **immutable** after creation (rename updates `name` only, never moves directories).
- All JSON writes are **atomic** (temp file + `File.rename`).
- Timestamps stored as ISO-8601 strings; dates as `YYYY-MM-DD`.
- Invoice numbers compared/sorted by `.to_i`, never lexically. `num` is assigned before an invoice's first write.
- Tests use a temp `DATA_DIR` per example (`Store.data_root=` override, reset after).
- TDD: write the failing test, watch it fail, implement minimally, watch it pass, commit. One logical change per commit.
- Commit messages end with the repo's co-author trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File Structure

**New (library):**
- `lib/store.rb` — requires the store files; defines `Store::APP_ROOT`, `Store.data_root`.
- `lib/store/json_store.rb` — low-level atomic read/write/list + slugify (module `Store`).
- `lib/store/formattable.rb` — `Formattable#format_number` (moved from `models/models.rb`).
- `lib/store/service.rb` — `Service` embedded line-item value object.
- `lib/store/business.rb` — `Business` (replaces `Company` singleton); also holds client-collection methods.
- `lib/store/client.rb` — `Client`.
- `lib/store/invoice.rb` — `Invoice` (+ invoice-collection methods on `Client`).
- `lib/store/timesheet_period.rb` — `TimesheetPeriod` (+ `Client#timesheet_summary`, invoice→timesheet reconciliation).

**New (app):**
- `app/businesses.rb` — business list / onboarding / select / logo route (mounted at `/`, replaces `Admin`).
- `views/businesses/index.erb`, `views/businesses/_form.erb` — list + onboarding form.

**Rewritten (app):**
- `config.ru`, `app/base.rb`, `app/clients.rb`, `app/invoices.rb`, `app/settings.rb`, `app/timesheets.rb`.
- Views under `views/clients/`, `views/invoices/`, `views/settings/`, `views/timesheets/`, and `views/admin/layout-default.erb` + `views/admin/home.erb`.

**New (script/tests):**
- `scripts/export_to_json.rb` — one-time SQLite → JSON export.
- `spec/store/*_spec.rb` — unit specs; `spec/requests/*_spec.rb` rewritten.

**Deleted (Task 13):** `app/auth.rb`, `lib/session_auth.rb`, `models/user.rb`, `models/models.rb`, `lib/mailer.rb`, `lib/action_mailer/*`, `lib/app/mailman.rb`, `scripts/send_approve_invoices.rb`, `db/` (migrations, `migrate.rb`, `seeds.rb`, `load_json.rb`), `views/auth/*`, `views/admin/layout-login.erb`, `views/invoices/html_email.erb`, `views/invoices/text_email.erb`, `spec/requests/auth_spec.rb`, `spec/models/user_spec.rb`.

---

## Task 1: `Store` foundation — atomic JSON I/O + slugify

**Files:**
- Create: `lib/store.rb`
- Create: `lib/store/json_store.rb`
- Test: `spec/store/json_store_spec.rb`
- Modify: `spec/spec_helper.rb` (add temp-data-root helper)

**Interfaces:**
- Produces:
  - `Store::APP_ROOT` → String (repo root)
  - `Store.data_root` → String; `Store.data_root=(path)` (test override)
  - `Store.slugify(name, taken: []) -> String`
  - `Store.read_json(path) -> Hash(symbol keys) | nil`
  - `Store.write_json(path, hash) -> path` (atomic; creates parent dirs)
  - `Store.list_dirs(path) -> [String]` (entry names, sorted; `[]` if absent)
  - `Store.list_files(path, ext) -> [String]` (names ending in `ext`, sorted; `[]` if absent)
  - `Store.now_iso -> String`
  - `Store.move(src, dest)` (creates dest parent, moves file or dir)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/store/json_store_spec.rb
require 'spec_helper'

RSpec.describe Store do
  around { |ex| with_temp_data_root { ex.run } }

  it 'slugifies names and de-dupes against taken slugs' do
    expect(Store.slugify('Acme Consulting, LLC')).to eq('acme-consulting-llc')
    expect(Store.slugify('  Wiz__Bang  ')).to eq('wiz-bang')
    dup = Store.slugify('Acme', taken: ['acme'])
    expect(dup).to match(/\Aacme-\d{1,3}\z/)
  end

  it 'writes and reads JSON atomically with symbol keys' do
    path = File.join(Store.data_root, 'a', 'b', 'x.json')
    Store.write_json(path, { name: 'X', n: 1 })
    expect(File.exist?(path)).to be true
    expect(Store.read_json(path)).to eq(name: 'X', n: 1)
    expect(Store.read_json(File.join(Store.data_root, 'missing.json'))).to be_nil
  end

  it 'lists directory and file names, empty when absent' do
    FileUtils.mkdir_p(File.join(Store.data_root, 'biz', 'clients', 'a'))
    FileUtils.mkdir_p(File.join(Store.data_root, 'biz', 'clients', 'b'))
    Store.write_json(File.join(Store.data_root, 'biz', 'x.json'), {})
    expect(Store.list_dirs(File.join(Store.data_root, 'biz', 'clients'))).to eq(%w[a b])
    expect(Store.list_files(File.join(Store.data_root, 'biz'), '.json')).to eq(['x.json'])
    expect(Store.list_dirs(File.join(Store.data_root, 'nope'))).to eq([])
  end
end
```

- [ ] **Step 2: Add the temp-data-root helper to spec_helper**

```ruby
# spec/spec_helper.rb  — add near the top (after requires)
require 'tmpdir'
require 'fileutils'
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'store'

module DataRootHelper
  def with_temp_data_root
    dir = Dir.mktmpdir('simply-suite-spec')
    prev = Store.instance_variable_get(:@data_root)
    Store.data_root = dir
    yield
  ensure
    Store.instance_variable_set(:@data_root, prev)
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end
end

RSpec.configure { |c| c.include DataRootHelper }
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/store/json_store_spec.rb`
Expected: FAIL — `cannot load such file -- store` / `uninitialized constant Store`.

- [ ] **Step 4: Implement `lib/store.rb`**

```ruby
# lib/store.rb
require 'json'
require 'fileutils'
require 'securerandom'
require 'date'

module Store
  APP_ROOT = File.expand_path('..', __dir__)

  class << self
    attr_writer :data_root

    def data_root
      @data_root ||= ENV.fetch('DATA_DIR', File.join(APP_ROOT, 'data'))
    end
  end
end

require 'store/json_store'
require 'store/formattable'
require 'store/service'
require 'store/business'
require 'store/client'
require 'store/invoice'
require 'store/timesheet_period'
```

Note: the later `require`s reference files created in Tasks 2–6. Until those files exist the require will fail, so during Task 1 temporarily comment out every `require 'store/…'` line except `json_store`, and re-enable each as its task lands. (The final state has them all enabled.)

- [ ] **Step 5: Implement `lib/store/json_store.rb`**

```ruby
# lib/store/json_store.rb
module Store
  module_function

  def slugify(name, taken: [])
    base = name.to_s.downcase
              .gsub(/[^\w\s-]/, '')
              .gsub(/[\s_]+/, '-')
              .gsub(/-+/, '-')
              .gsub(/\A-|-\z/, '')
    base = 'item' if base.empty?
    slug = base
    slug = "#{base}-#{rand(100)}" while taken.include?(slug)
    slug
  end

  def read_json(path)
    return nil unless File.exist?(path)
    JSON.parse(File.read(path), symbolize_names: true)
  end

  def write_json(path, hash)
    FileUtils.mkdir_p(File.dirname(path))
    tmp = "#{path}.tmp.#{SecureRandom.hex(4)}"
    File.write(tmp, JSON.pretty_generate(hash))
    File.rename(tmp, path)
    path
  end

  def list_dirs(path)
    return [] unless File.directory?(path)
    Dir.children(path).select { |e| File.directory?(File.join(path, e)) }.sort
  end

  def list_files(path, ext)
    return [] unless File.directory?(path)
    Dir.children(path).select { |e| e.end_with?(ext) && File.file?(File.join(path, e)) }.sort
  end

  def now_iso
    Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
  end

  def move(src, dest)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.mv(src, dest)
  end
end
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bundle exec rspec spec/store/json_store_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 7: Commit**

```bash
git add lib/store.rb lib/store/json_store.rb spec/store/json_store_spec.rb spec/spec_helper.rb
git commit -m "feat: add Store foundation — atomic JSON I/O and slugify

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `Formattable` mixin + `Service` value object

**Files:**
- Create: `lib/store/formattable.rb`
- Create: `lib/store/service.rb`
- Test: `spec/store/service_spec.rb`

**Interfaces:**
- Consumes: `Store` (Task 1).
- Produces:
  - `Formattable#format_number(n, d) -> String` (thousands-separated)
  - `Service.new(hash)` where hash keys `:item,:desc,:service_date,:qty,:cost`
  - `Service#item #desc #service_date(Date|nil) #qty(Float) #cost(Float)`
  - `Service#formatted_service_date #formatted_cost #formatted_line_total`
  - `Service#to_h -> Hash` (for persistence; `service_date` as `YYYY-MM-DD` or nil)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/store/service_spec.rb
require 'spec_helper'

RSpec.describe Store::Service do
  it 'exposes fields and formatted helpers' do
    s = Store::Service.new(item: 'Dev', desc: 'work', service_date: '2026-07-05', qty: 2.0, cost: 125.0)
    expect(s.item).to eq('Dev')
    expect(s.service_date).to eq(Date.new(2026, 7, 5))
    expect(s.formatted_service_date).to eq('07/05/2026')
    expect(s.formatted_cost).to eq('125.00')
    expect(s.formatted_line_total).to eq('250.00')
  end

  it 'round-trips to_h with a date string and tolerates blanks' do
    s = Store::Service.new(item: 'X', desc: nil, service_date: nil, qty: 1, cost: 10)
    expect(s.formatted_service_date).to eq('')
    expect(s.to_h).to eq(item: 'X', desc: nil, service_date: nil, qty: 1.0, cost: 10.0)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/store/service_spec.rb`
Expected: FAIL — `uninitialized constant Store::Service`.

- [ ] **Step 3: Implement `lib/store/formattable.rb`**

```ruby
# lib/store/formattable.rb
module Store
  module Formattable
    def format_number(n, d)
      ('%.*f' % [d, n.to_f]).gsub(/(\d)(?=(\d\d\d)+(?!\d))/, '\\1,')
    end
  end
end
```

- [ ] **Step 4: Implement `lib/store/service.rb`**

```ruby
# lib/store/service.rb
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
```

- [ ] **Step 5: Enable the `service`/`formattable` requires in `lib/store.rb`** (uncomment them), then run:

Run: `bundle exec rspec spec/store/service_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 6: Commit**

```bash
git add lib/store/formattable.rb lib/store/service.rb lib/store.rb spec/store/service_spec.rb
git commit -m "feat: add Formattable mixin and Service line-item value object

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `Business` model (replaces the Company singleton)

**Files:**
- Create: `lib/store/business.rb`
- Test: `spec/store/business_spec.rb`

**Interfaces:**
- Consumes: `Store` (Task 1).
- Produces:
  - `Business.all -> [Business]` (sorted by name)
  - `Business.find(slug) -> Business | nil`
  - `Business.create(attrs, logo_src = nil) -> Business` — `attrs`: `:name,:contact,:email,:street,:city,:state,:zip`; optional `:defaults`. `logo_src` = path to an image to copy to `config/logo.png`.
  - Instance readers: `#slug #name #contact #email #street #city #state #zip #defaults`
  - `#update(attrs) -> self` (writes `config/settings.json`; never changes slug)
  - `#save_logo(src_path) -> String` (copies to `config/logo.png`)
  - `#logo_file -> String | nil` (path to `config/logo.png` if it exists)
  - `#resolve_logo -> { local:, web: } | nil` (`web` = `/businesses/logo?v=<mtime>`)
  - `#city_state_zip -> String`
  - `#dir -> String`
  - `#to_h -> Hash`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/store/business_spec.rb
require 'spec_helper'

RSpec.describe Store::Business do
  around { |ex| with_temp_data_root { ex.run } }

  let(:attrs) do
    { name: 'Acme Consulting, LLC', contact: 'Me', email: 'a@x.com',
      street: '1 Main', city: 'Charlotte', state: 'NC', zip: '28203' }
  end

  it 'creates a business dir with settings.json and default period monthly' do
    b = Store::Business.create(attrs)
    expect(b.slug).to eq('acme-consulting-llc')
    expect(File.exist?(File.join(Store.data_root, 'acme-consulting-llc', 'config', 'settings.json'))).to be true
    expect(b.defaults[:timesheet_period]).to eq('monthly')
    expect(b.city_state_zip).to eq('Charlotte, NC 28203')
  end

  it 'lists and finds businesses, de-duping slugs' do
    Store::Business.create(attrs)
    b2 = Store::Business.create(attrs.merge(name: 'Acme Consulting, LLC'))
    expect(b2.slug).to match(/\Aacme-consulting-llc-\d/)
    expect(Store::Business.all.map(&:slug)).to include('acme-consulting-llc', b2.slug)
    expect(Store::Business.find('acme-consulting-llc').name).to eq('Acme Consulting, LLC')
    expect(Store::Business.find('nope')).to be_nil
  end

  it 'updates fields without moving the directory and saves a logo' do
    b = Store::Business.create(attrs)
    b.update(contact: 'New Contact', defaults: { timesheet_period: 'weekly' })
    expect(Store::Business.find(b.slug).contact).to eq('New Contact')
    expect(Store::Business.find(b.slug).defaults[:timesheet_period]).to eq('weekly')

    src = File.join(Store.data_root, 'src.png')
    File.write(src, 'PNGDATA')
    b.save_logo(src)
    expect(b.logo_file).to eq(File.join(b.dir, 'config', 'logo.png'))
    expect(b.resolve_logo[:web]).to match(%r{\A/businesses/logo\?v=\d+\z})
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/store/business_spec.rb`
Expected: FAIL — `uninitialized constant Store::Business`.

- [ ] **Step 3: Implement `lib/store/business.rb`**

```ruby
# lib/store/business.rb
module Store
  class Business
    FIELDS = %i[name contact email street city state zip].freeze
    DEFAULTS = { timesheet_period: 'monthly',
                 terms: 'Payable upon receipt',
                 notes: 'Thank you for your business' }.freeze

    attr_reader :slug, :data

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

    def to_h
      @data
    end
  end
end
```

- [ ] **Step 4: Enable `require 'store/business'` in `lib/store.rb`, run:**

Run: `bundle exec rspec spec/store/business_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

```bash
git add lib/store/business.rb lib/store.rb spec/store/business_spec.rb
git commit -m "feat: add Business model backed by config/settings.json

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `Client` model (+ client collection on Business)

**Files:**
- Create: `lib/store/client.rb`
- Modify: `lib/store/business.rb` (add `#clients`, `#find_client`, `#create_client`)
- Test: `spec/store/client_spec.rb`

**Interfaces:**
- Consumes: `Business` (Task 3), `Store` (Task 1).
- Produces:
  - `Business#clients -> [Client]` (sorted by name)
  - `Business#find_client(slug) -> Client | nil`
  - `Business#create_client(attrs) -> Client` (`attrs[:name]` required; sets slug once; `attrs[:prefix]` etc.)
  - `Client#business #slug #prefix #name #contact #email #street #street2 #city #state #zip`
  - `Client#timesheet_period_override -> String | nil`
  - `Client#update(attrs) -> self` (never changes slug)
  - `Client#soft_delete` (moves dir → `clients/archive/<slug>`)
  - `Client#dir -> String`
  - `Client#resolved_timesheet_period -> String` (override else business default)
  - `Client#to_h`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/store/client_spec.rb
require 'spec_helper'

RSpec.describe Store::Client do
  around { |ex| with_temp_data_root { ex.run } }

  let(:biz) do
    Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com',
                           street: '1', city: 'CLT', state: 'NC', zip: '28203')
  end

  let(:cattrs) do
    { name: 'Widgets Inc', prefix: 'WID', contact: 'Jane', email: 'j@w.com',
      street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203' }
  end

  it 'creates a client with a slug and client.json' do
    c = biz.create_client(cattrs)
    expect(c.slug).to eq('widgets-inc')
    expect(c.prefix).to eq('WID')
    expect(File.exist?(File.join(c.dir, 'client.json'))).to be true
    expect(biz.find_client('widgets-inc').name).to eq('Widgets Inc')
    expect(biz.clients.map(&:slug)).to eq(['widgets-inc'])
  end

  it 'inherits the business timesheet period unless overridden' do
    c = biz.create_client(cattrs)
    expect(c.resolved_timesheet_period).to eq('monthly')
    c.update(timesheet_period: 'weekly')
    expect(biz.find_client(c.slug).resolved_timesheet_period).to eq('weekly')
  end

  it 'soft-deletes by moving the folder into clients/archive' do
    c = biz.create_client(cattrs)
    c.soft_delete
    expect(biz.find_client('widgets-inc')).to be_nil
    expect(File.exist?(File.join(biz.dir, 'clients', 'archive', 'widgets-inc', 'client.json'))).to be true
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/store/client_spec.rb`
Expected: FAIL — `undefined method 'create_client'` / `uninitialized constant Store::Client`.

- [ ] **Step 3: Add collection methods to `lib/store/business.rb`** (inside `class Business`)

```ruby
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
      slug = Store.slugify(attrs[:name], taken: Store.list_dirs(clients_dir))
      data = { slug: slug }
      Client::FIELDS.each { |f| data[f] = attrs[f] }
      data[:timesheet_period] = attrs[:timesheet_period]
      data[:created_at] = Store.now_iso
      data[:updated_at] = data[:created_at]
      c = Client.new(self, data)
      Store.write_json(File.join(c.dir, 'client.json'), data)
      c
    end
```

- [ ] **Step 4: Implement `lib/store/client.rb`**

```ruby
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
```

- [ ] **Step 5: Enable `require 'store/client'`, run:**

Run: `bundle exec rspec spec/store/client_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 6: Commit**

```bash
git add lib/store/client.rb lib/store/business.rb lib/store.rb spec/store/client_spec.rb
git commit -m "feat: add Client model and client collection on Business

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `Invoice` model (embedded services, numbering, PDF paths)

**Files:**
- Create: `lib/store/invoice.rb`
- Test: `spec/store/invoice_spec.rb`

**Interfaces:**
- Consumes: `Client` (Task 4), `Service` (Task 2).
- Produces:
  - `Client#invoices -> [Invoice]` (sorted by `num.to_i` desc)
  - `Client#find_invoice(num) -> Invoice | nil`
  - `Client#create_invoice(attrs) -> Invoice` (assigns `next_num` when `attrs[:num]` blank; writes file)
  - `Client#next_num -> String` (zero-padded to existing width, default 3)
  - `Client#invoices_dir -> String`
  - `Invoice#client #num #invoice_date(Date|nil) #total_amount #total_discount #amount_paid #is_complete #terms #notes #approved_on #sent_at #paid_at`
  - `Invoice#services -> [Service]`
  - `Invoice#update(attrs) -> self` (`attrs[:services]` = array of row hashes → replaces services; recomputes nothing else)
  - `Invoice#soft_delete` (moves json + pdf → `invoices/archive/`) — timesheet reconciliation added in Task 6
  - `Invoice#formatted_invoice_num #formatted_invoice_date #formatted_total_amount #formatted_total_discount #formatted_discount_percentage #formatted_discount_total_amount #formatted_final_amount #formatted_amount_paid #formatted_terms #formatted_notes #formatted_sent_date #formatted_paid_date`
  - `Invoice#get_status -> String` · `#deletable? -> Bool` · `#editable? -> Bool`
  - `Invoice#pdf_filename -> "PREFIX-NUM.pdf"` · `#pdf_path -> String` · `#pdf_exists? -> Bool`
  - `Invoice#json_path -> String`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/store/invoice_spec.rb
require 'spec_helper'

RSpec.describe Store::Invoice do
  around { |ex| with_temp_data_root { ex.run } }

  let(:biz) { Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203') }
  let(:client) { biz.create_client(name: 'Widgets Inc', prefix: 'WID', contact: 'J', email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203') }

  it 'assigns the next number and embeds services' do
    inv = client.create_invoice(invoice_date: '2026-07-09', terms: 'Net 30', notes: 'thanks',
                                total_amount: 250.0, total_discount: 0, amount_paid: 0,
                                services: [{ item: 'Dev', desc: 'x', service_date: '2026-07-05', qty: 2, cost: 125 }])
    expect(inv.num).to eq('001')
    expect(File.exist?(File.join(client.invoices_dir, '001.json'))).to be true
    expect(inv.services.first.formatted_line_total).to eq('250.00')
    expect(inv.pdf_filename).to eq('WID-001.pdf')

    inv2 = client.create_invoice(invoice_date: '2026-07-10', services: [])
    expect(inv2.num).to eq('002')
    expect(client.invoices.map(&:num)).to eq(%w[002 001])
  end

  it 'pads next_num to the existing width (handles mixed widths by value)' do
    client.create_invoice(num: '9', services: [])
    client.create_invoice(num: '10', services: [])
    expect(client.next_num).to eq('11')
  end

  it 'derives status and soft-deletes json + pdf into archive' do
    inv = client.create_invoice(services: [])
    FileUtils.mkdir_p(File.dirname(inv.pdf_path))
    File.write(inv.pdf_path, '%PDF')
    expect(inv.get_status).to eq('draft')
    inv.soft_delete
    expect(client.find_invoice(inv.num)).to be_nil
    expect(File.exist?(File.join(client.invoices_dir, 'archive', "#{inv.num}.json"))).to be true
    expect(File.exist?(File.join(client.invoices_dir, 'archive', inv.pdf_filename))).to be true
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/store/invoice_spec.rb`
Expected: FAIL — `undefined method 'create_invoice'`.

- [ ] **Step 3: Add invoice collection methods to `lib/store/client.rb`** (inside `class Client`)

```ruby
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
      nums = Store.list_files(invoices_dir, '.json').map { |f| File.basename(f, '.json') }
      return '001' if nums.empty?
      width = nums.map(&:length).max            # pad to widest existing (no forced min once numbers exist)
      max   = nums.map(&:to_i).max
      format("%0#{width}d", max + 1)
    end

    def create_invoice(attrs)
      num = attrs[:num].to_s.empty? ? next_num : attrs[:num].to_s
      inv = Invoice.new(self, Invoice.blank_data(num))
      inv.update(attrs.merge(num: num))
      inv
    end
```

- [ ] **Step 4: Implement `lib/store/invoice.rb`**

```ruby
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
      Store.move(json_path, File.join(client.invoices_dir, 'archive', "#{num}.json"))
      Store.move(pdf_path, File.join(client.invoices_dir, 'archive', pdf_filename)) if pdf_exists?
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
```

Add `require 'time'` at the top of `lib/store.rb` (for `Time.parse`).

- [ ] **Step 5: Enable `require 'store/invoice'`, run:**

Run: `bundle exec rspec spec/store/invoice_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 6: Commit**

```bash
git add lib/store/invoice.rb lib/store/client.rb lib/store.rb spec/store/invoice_spec.rb
git commit -m "feat: add Invoice model with embedded services, numbering, archive

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `TimesheetPeriod` model (bucketing, roll-up, reconciliation)

**Files:**
- Create: `lib/store/timesheet_period.rb`
- Modify: `lib/store/client.rb` (add `#timesheet_period`, `#timesheet_summary`, `#timesheets_dir`)
- Modify: `lib/store/invoice.rb` (`#soft_delete` reconciles timesheet entries)
- Test: `spec/store/timesheet_period_spec.rb`

**Interfaces:**
- Consumes: `Client`, `Invoice`.
- Produces:
  - `TimesheetPeriod.key_for(date, granularity) -> String` (`daily`→`YYYY-MM-DD`, `weekly`→`YYYY-Www`, `monthly`→`YYYY-MM`, `quarterly`→`YYYY-Qn`)
  - `Client#timesheets_dir -> String`
  - `Client#timesheet_period(key = nil) -> TimesheetPeriod` (key defaults to current period for today)
  - `Client#timesheet_summary -> { total:, uninvoiced: }` (scans all period files)
  - `TimesheetPeriod#key #granularity #entries([Hash])`
  - `TimesheetPeriod#apply(rows:, deletes:)` — upsert submitted rows (generate id when absent; skip invoiced), re-bucket rows whose date maps to another period, move deleted ids to `archive/<key>.json`; persists.
  - `TimesheetPeriod#prev_key -> String` · `#next_key -> String`
  - `TimesheetPeriod#create_invoice -> Invoice | nil` (rolls un-invoiced entries; nil if none)
  - `Invoice#soft_delete` also resets matching timesheet entries to `invoiced:false, invoice_num:nil`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/store/timesheet_period_spec.rb
require 'spec_helper'

RSpec.describe Store::TimesheetPeriod do
  around { |ex| with_temp_data_root { ex.run } }

  let(:biz) { Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203') }
  let(:client) { biz.create_client(name: 'Widgets Inc', prefix: 'WID', contact: 'J', email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203') }

  it 'computes period keys per granularity' do
    d = Date.new(2026, 7, 5)
    expect(described_class.key_for(d, 'daily')).to eq('2026-07-05')
    expect(described_class.key_for(d, 'monthly')).to eq('2026-07')
    expect(described_class.key_for(d, 'quarterly')).to eq('2026-Q3')
    expect(described_class.key_for(d, 'weekly')).to eq('2026-W27')
  end

  it 'adds entries with generated ids and buckets by service_date' do
    p = client.timesheet_period('2026-07')
    p.apply(rows: [{ item: 'Dev', desc: 'x', service_date: '2026-07-05', qty: 2, cost: 125 }], deletes: [])
    reloaded = client.timesheet_period('2026-07')
    expect(reloaded.entries.size).to eq(1)
    expect(reloaded.entries.first[:id]).to match(/\A[0-9a-f]{6}\z/)
    expect(client.timesheet_summary).to eq(total: 1, uninvoiced: 1)
  end

  it 're-buckets an entry into another period when its service_date changes' do
    client.timesheet_period('2026-07').apply(
      rows: [{ item: 'Dev', desc: 'x', service_date: '2026-07-05', qty: 1, cost: 100 }], deletes: []
    )
    id = client.timesheet_period('2026-07').entries.first[:id]
    client.timesheet_period('2026-07').apply(
      rows: [{ id: id, item: 'Dev', desc: 'x', service_date: '2026-08-03', qty: 1, cost: 100 }], deletes: []
    )
    expect(client.timesheet_period('2026-07').entries).to be_empty
    expect(client.timesheet_period('2026-08').entries.map { |e| e[:id] }).to eq([id])
  end

  it 'rolls a period into a draft invoice and marks entries invoiced' do
    p = client.timesheet_period('2026-07')
    p.apply(rows: [{ item: 'Dev', desc: 'x', service_date: '2026-07-05', qty: 2, cost: 125 }], deletes: [])
    inv = client.timesheet_period('2026-07').create_invoice
    expect(inv.num).to eq('001')
    expect(inv.services.first.item).to eq('Dev')
    expect(inv.total_amount).to eq(250.0)
    expect(client.timesheet_summary).to eq(total: 1, uninvoiced: 0)
    expect(client.timesheet_period('2026-07').create_invoice).to be_nil # nothing left
  end

  it 'un-invoices entries when the invoice is soft-deleted' do
    p = client.timesheet_period('2026-07')
    p.apply(rows: [{ item: 'Dev', desc: 'x', service_date: '2026-07-05', qty: 1, cost: 100 }], deletes: [])
    inv = client.timesheet_period('2026-07').create_invoice
    inv.soft_delete
    expect(client.timesheet_summary).to eq(total: 1, uninvoiced: 1)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/store/timesheet_period_spec.rb`
Expected: FAIL — `uninitialized constant Store::TimesheetPeriod`.

- [ ] **Step 3: Add timesheet methods to `lib/store/client.rb`** (inside `class Client`)

```ruby
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
```

- [ ] **Step 4: Implement `lib/store/timesheet_period.rb`**

```ruby
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
```

- [ ] **Step 5: Add reconciliation to `Invoice#soft_delete`** in `lib/store/invoice.rb`

Replace the `soft_delete` method with:

```ruby
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
```

- [ ] **Step 6: Enable `require 'store/timesheet_period'`, run:**

Run: `bundle exec rspec spec/store/timesheet_period_spec.rb`
Expected: PASS (4 examples).

- [ ] **Step 7: Run the whole store suite**

Run: `bundle exec rspec spec/store`
Expected: PASS (all examples green).

- [ ] **Step 8: Commit**

```bash
git add lib/store/timesheet_period.rb lib/store/client.rb lib/store/invoice.rb lib/store.rb spec/store/timesheet_period_spec.rb
git commit -m "feat: add TimesheetPeriod bucketing, roll-into-invoice, reconciliation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Boot on the store — `config.ru` + `app/base.rb`

**Files:**
- Modify: `config.ru` (remove DB/mail/User; mount new apps)
- Modify: `app/base.rb` (remove auth; add business helpers; drop static pdf/logo routes)
- Test: `spec/requests/boot_spec.rb`

**Interfaces:**
- Produces (helpers on `SimplyBase`):
  - `#current_business -> Store::Business | nil` (from `session[:business]`)
  - `#require_business!` (redirect to `/businesses` if none)
  - keeps `#v(template, options)` view helper, `not_found`/`error` handlers
- Consumes: `Store` (Tasks 1–6).

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/boot_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Boot', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end

  around { |ex| with_temp_data_root { ex.run } }

  it 'redirects to /businesses when no business is selected' do
    get '/'
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include('/businesses')
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/boot_spec.rb`
Expected: FAIL — the current `config.ru` requires Sequel/`DATABASE_URL` and mounts `Auth`, so it errors on load.

- [ ] **Step 3: Rewrite `config.ru`**

```ruby
require 'dotenv'
Dotenv.load

$:.unshift File.expand_path('lib', __dir__)
$:.unshift File.expand_path('config', __dir__)
$:.unshift File.expand_path('app', __dir__)

require 'store'
require 'sinatra/base'
require 'base'

map '/clients'    do require 'clients';    run Clients    end
map '/invoices'   do require 'invoices';   run Invoices   end
map '/settings'   do require 'settings';   run Settings   end
map '/timesheets' do require 'timesheets'; run Timesheets end
map '/businesses' do require 'businesses'; run Businesses  end
map '/'           do require 'dashboard';  run Dashboard  end
```

- [ ] **Step 4: Rewrite `app/base.rb`**

```ruby
require 'json'
require 'sinatra/content_for'
require 'sinatra/flash'

STATUS_COLORS = {
  'paid'     => 'bg-green-100 text-green-800',
  'late'     => 'bg-red-100 text-red-800',
  'sent'     => 'bg-blue-100 text-blue-800',
  'approved' => 'bg-yellow-100 text-yellow-800',
  'draft'    => 'bg-gray-100 text-gray-700'
}.freeze

class SimplyBase < Sinatra::Base
  helpers Sinatra::ContentFor
  register Sinatra::Flash

  set :views,          File.join(File.dirname(File.dirname(__FILE__)), 'views')
  set :public_folder,  File.join(File.dirname(File.dirname(__FILE__)), 'public')
  set :run,            false
  set :environment,    ENV.fetch('RACK_ENV', 'development').to_sym
  set :layout,         true
  set :logging,        true
  set :sessions,       true
  set :session_secret, ENV.fetch('SESSION_SECRET', SecureRandom.hex(64))
  set :erb, escape_html: true
  set :layout_default, :'admin/layout-default'

  use Rack::Static, urls: ['/css', '/js', '/favicon.ico', '/favicon.gif'], root: 'public'

  before do
    headers 'Content-Type' => 'text/html; charset=utf-8'
  end

  configure :development do
    set :reload_templates, true
  end

  def current_business
    slug = session[:business]
    @current_business ||= slug ? Store::Business.find(slug) : nil
  end

  def require_business!
    redirect '/businesses' unless current_business
  end

  def v(template, options = {})
    options[:layout] ||= settings.layout_default
    options[:layout] = false if request.xhr?
    erb(template, options)
  end

  not_found do
    @page_title = 'Not Found'
    v :'admin/not_found', layout: :'admin/layout'
  end

  error do
    @page_title = 'Error'
    v :'admin/error', layout: :'admin/layout'
  end
end
```

- [ ] **Step 5: Create `app/dashboard.rb` and a stub `app/businesses.rb`**

`Rack::Builder.parse_file` / `#to_app` builds the URLMap **eagerly** — every `require` inside every `map` block runs at build time (this is not lazy and not Rack-version-dependent). `config.ru` maps `dashboard` and `businesses`, neither of which exists yet, so both files must exist before the boot spec can build the app. The `clients`/`invoices`/`settings`/`timesheets` files still exist (old versions) and load fine at this point — they reference removed helpers/models only inside route blocks, which the boot spec never reaches. Create:

```ruby
# app/dashboard.rb
class Dashboard < SimplyBase
  before { require_business! }

  get '/?' do
    @page_title = 'Dashboard'
    v :'admin/home'
  end
end
```

```ruby
# app/businesses.rb  — stub; fully implemented in Task 8
class Businesses < SimplyBase
end
```

- [ ] **Step 6: Run to verify it passes**

Run: `bundle exec rspec spec/requests/boot_spec.rb`
Expected: PASS — `GET /` routes to `Dashboard`, whose `require_business!` redirects (302) to `/businesses` since the session has no business.

- [ ] **Step 7: Commit**

```bash
git add config.ru app/base.rb app/dashboard.rb app/businesses.rb spec/requests/boot_spec.rb
git commit -m "feat: boot on the JSON store; drop DB/auth/email from base + config.ru

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: `Businesses` controller — onboarding, switcher, logo route, dashboard

**Files:**
- Create: `app/businesses.rb`
- Create: `views/businesses/index.erb`, `views/businesses/_form.erb`
- Modify: `views/admin/home.erb` (dashboard: greet the active business, link to clients/timesheets/settings, switcher)
- Modify: `views/admin/layout-default.erb` (replace "Sign out" with the business name + "Switch business" link)
- Test: `spec/requests/businesses_spec.rb`

**Interfaces:**
- Consumes: `current_business`, `Store::Business`.
- Produces routes:
  - `GET /businesses` — list businesses (or onboarding form when none)
  - `POST /businesses` — create (`params[:business]` + `params[:logo]` upload) → sets `session[:business]`, redirect `/`
  - `POST /businesses/:slug/select` — set `session[:business]`, redirect `/`
  - `GET /businesses/logo` — stream the active business's `config/logo.png` (404 if none)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/businesses_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Businesses', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end
  around { |ex| with_temp_data_root { ex.run } }

  it 'shows onboarding when there are no businesses' do
    get '/businesses'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to match(/Create.*business/i)
  end

  it 'creates a business and selects it' do
    post '/businesses', business: { name: 'Acme Consulting', contact: 'Me', email: 'a@x.com',
                                    street: '1 Main', city: 'CLT', state: 'NC', zip: '28203' }
    expect(last_response.status).to eq(302)
    follow_redirect!
    expect(Store::Business.all.map(&:slug)).to include('acme-consulting')
    # session now has the business -> dashboard renders
    get '/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Acme Consulting')
  end

  it 'streams the active business logo and 404s when absent' do
    post '/businesses', business: { name: 'Logoed', contact: 'M', email: 'l@x.com',
                                    street: '1', city: 'CLT', state: 'NC', zip: '28203' }
    get '/businesses/logo'                # no logo uploaded yet
    expect(last_response.status).to eq(404)

    Store::Business.find('logoed').save_logo(File.expand_path('../../docs/invoice-screenshot.png', __dir__))
    get '/businesses/logo'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('image')
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/businesses_spec.rb`
Expected: FAIL — `Businesses` route/view missing.

- [ ] **Step 3: Implement `app/businesses.rb`**

```ruby
require 'fileutils'

class Businesses < SimplyBase
  set :layout_default, :'admin/layout-default'

  get '/?' do
    @businesses = Store::Business.all
    @page_title = @businesses.empty? ? 'Welcome' : 'Choose a business'
    v :'businesses/index'
  end

  post '/?' do
    p = params[:business] || {}
    if p[:name].to_s.strip.empty?
      flash[:error] = 'Business name is required.'
      redirect '/businesses'
    end
    logo_src = nil
    upload = params[:logo]
    if upload && upload[:tempfile] && upload[:type].to_s.start_with?('image/')
      logo_src = upload[:tempfile].path
    end
    biz = Store::Business.create(
      { name: p[:name], contact: p[:contact], email: p[:email],
        street: p[:street], city: p[:city], state: p[:state], zip: p[:zip] },
      logo_src
    )
    session[:business] = biz.slug
    flash[:success] = "#{biz.name} created."
    redirect '/'
  end

  post '/:slug/select' do
    biz = Store::Business.find(params[:slug])
    halt 404 unless biz
    session[:business] = biz.slug
    redirect '/'
  end

  get '/logo' do
    biz = current_business
    halt 404 unless biz && biz.logo_file
    send_file biz.logo_file, type: 'image/png', disposition: 'inline'
  end
end
```

- [ ] **Step 4: Implement `views/businesses/index.erb`**

```erb
<% if @businesses.empty? %>
  <div class="max-w-lg mx-auto mt-16">
    <h1 class="text-2xl font-semibold mb-2">Welcome to Simply Suite</h1>
    <p class="text-gray-600 mb-6">Create your first business to get started.</p>
    <%= erb :'businesses/_form' %>
  </div>
<% else %>
  <div class="max-w-2xl mx-auto mt-12">
    <h1 class="text-2xl font-semibold mb-6">Choose a business</h1>
    <ul class="divide-y border rounded mb-10">
      <% @businesses.each do |b| %>
        <li class="flex items-center justify-between px-4 py-3">
          <span><%= b.name %></span>
          <form method="post" action="/businesses/<%= b.slug %>/select">
            <button class="text-blue-600 hover:underline" type="submit">Open →</button>
          </form>
        </li>
      <% end %>
    </ul>
    <h2 class="text-lg font-medium mb-3">Create a new business</h2>
    <%= erb :'businesses/_form' %>
  </div>
<% end %>
```

- [ ] **Step 5: Implement `views/businesses/_form.erb`**

```erb
<form method="post" action="/businesses" enctype="multipart/form-data" class="space-y-3">
  <% [['Business name','name'],['Contact','contact'],['Email','email'],
      ['Street','street'],['City','city'],['State','state'],['ZIP','zip']].each do |label, field| %>
    <div>
      <label class="block text-sm text-gray-600"><%= label %></label>
      <input class="w-full border rounded px-3 py-2" type="text" name="business[<%= field %>]">
    </div>
  <% end %>
  <div>
    <label class="block text-sm text-gray-600">Logo (optional)</label>
    <input type="file" name="logo" accept="image/*">
  </div>
  <button class="bg-blue-600 text-white px-4 py-2 rounded" type="submit">Create business</button>
</form>
```

- [ ] **Step 6: Update `views/admin/home.erb`** — make it greet `current_business` and link to the sections. Replace its body with:

```erb
<% @business = current_business %>
<div class="max-w-3xl mx-auto mt-10">
  <h1 class="text-2xl font-semibold mb-1"><%= @business.name %></h1>
  <p class="text-gray-600 mb-8">Dashboard</p>
  <div class="grid grid-cols-3 gap-4">
    <a class="border rounded p-6 hover:bg-gray-50" href="/clients">Clients</a>
    <a class="border rounded p-6 hover:bg-gray-50" href="/timesheets">Timesheets</a>
    <a class="border rounded p-6 hover:bg-gray-50" href="/settings">Settings</a>
  </div>
</div>
```

- [ ] **Step 7: Update `views/admin/layout-default.erb`** — replace the "Sign out" link with the business switcher. Find the nav element containing the sign-out link (grep for `logout` / `Sign out`) and replace it with:

```erb
<div class="flex items-center gap-3">
  <span class="text-sm text-gray-500"><%= current_business&.name %></span>
  <a class="text-sm text-blue-600 hover:underline" href="/businesses">Switch business</a>
</div>
```

Also remove the Stimulus `delete_services` tracking here later (Task 10) — leave other markup intact for now.

- [ ] **Step 8: Run to verify it passes**

Run: `bundle exec rspec spec/requests/businesses_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 9: Commit**

```bash
git add app/businesses.rb views/businesses app/dashboard.rb views/admin/home.erb views/admin/layout-default.erb spec/requests/businesses_spec.rb
git commit -m "feat: business onboarding, switcher, logo route, dashboard

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: `Clients` controller + views

**Files:**
- Modify: `app/clients.rb` (rewrite)
- Modify: `views/clients/list.erb`, `views/clients/view.erb`, `views/clients/_form.erb`, `views/clients/edit.erb`, `views/clients/create.erb`
- Test: `spec/requests/clients_spec.rb` (rewrite)

**Interfaces:**
- Consumes: `current_business`, `Store::Client`.
- Produces routes (all under `/clients`):
  - `GET /` (list), `GET /view/:client_key`, `GET /create`, `POST /create`,
    `GET /edit/:client_key`, `POST /:client_key` (update), `GET /delete/:client_key`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/clients_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Clients', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end

  around do |ex|
    with_temp_data_root do
      @biz = Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203')
      ex.run
    end
  end

  def select_business
    post "/businesses/#{@biz.slug}/select"
  end

  it 'creates, updates, lists and deletes a client' do
    select_business
    post '/clients/create', client: { name: 'Widgets Inc', client_prefix: 'WID', contact: 'J',
                                       email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203' }
    expect(@biz.find_client('widgets-inc')).not_to be_nil

    get '/clients'
    expect(last_response.body).to include('Widgets Inc')

    post '/clients/widgets-inc', client: { client_prefix: 'WID', name: 'Widgets LLC', contact: 'J',
                                           email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203' }
    expect(@biz.find_client('widgets-inc').name).to eq('Widgets LLC')

    get '/clients/delete/widgets-inc'
    expect(@biz.find_client('widgets-inc')).to be_nil
  end

  it 'redirects to /businesses without an active business' do
    get '/clients'
    expect(last_response.status).to eq(302)
    expect(last_response.location).to include('/businesses')
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/clients_spec.rb`
Expected: FAIL — old `Clients` uses Sequel `Client`.

- [ ] **Step 3: Rewrite `app/clients.rb`**

```ruby
class Clients < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { require_business! }

  get '/' do
    per_page = 25
    all = current_business.clients
    @page = [params[:page].to_i, 1].max
    @total_pages = [(all.size.to_f / per_page).ceil, 1].max
    @clients = all.slice((@page - 1) * per_page, per_page) || []
    @pagination_path = '/clients'
    @page_title = 'Clients'
    v :'clients/list'
  end

  get '/view/:client_key' do
    @client = current_business.find_client(params[:client_key])
    halt 404 unless @client
    @page_title = "Client: #{@client.name}"
    v :'clients/view'
  end

  # NOTE: literal `/create` routes MUST be declared before the parameterized
  # `post '/:client_key'` update route — Sinatra matches in definition order,
  # so otherwise POST /clients/create is swallowed by the update route.
  get '/create' do
    @client = nil
    @action_url = '/clients/create'
    @submit_value = 'Create'
    @page_title = 'New Client'
    v :'clients/create'
  end

  post '/create' do
    p = params[:client]
    if p[:name].to_s.strip.empty?
      flash.now[:error] = 'Name is required'
      @action_url = '/clients/create'; @submit_value = 'Create'; @page_title = 'New Client'
      @client = nil
      halt v(:'clients/create')
    end
    current_business.create_client(
      name: p[:name], prefix: p[:client_prefix], contact: p[:contact], email: p[:email],
      street: p[:street], street2: p[:street2], city: p[:city], state: p[:state], zip: p[:zip]
    )
    flash[:success] = 'Client created successfully'
    redirect '/clients'
  end

  get '/edit/:client_key' do
    @client = current_business.find_client(params[:client_key])
    halt 404 unless @client
    @action_url = "/clients/#{@client.slug}"
    @submit_value = 'Update'
    @page_title = "Edit #{@client.name}"
    v :'clients/edit'
  end

  post '/:client_key' do
    client = current_business.find_client(params[:client_key])
    halt 404 unless client
    p = params[:client]
    client.update(
      prefix: p[:client_prefix], name: p[:name], contact: p[:contact], email: p[:email],
      street: p[:street], street2: p[:street2], city: p[:city], state: p[:state], zip: p[:zip],
      timesheet_period: (p[:timesheet_period].to_s.empty? ? nil : p[:timesheet_period])
    )
    flash[:success] = 'Client updated successfully'
    redirect '/clients'
  end

  get '/delete/:client_key' do
    client = current_business.find_client(params[:client_key])
    halt 404 unless client
    client.soft_delete
    flash[:success] = "#{client.name} and all their invoices have been deleted."
    redirect '/clients'
  end
end
```

- [ ] **Step 4: Update the client views.** In `views/clients/_form.erb`, `edit.erb`, `create.erb`, `list.erb`, `view.erb`:
  - Replace any `@client.client_key` with `@client.slug`, `client.client_key` with `client.slug`.
  - Replace `@client.client_prefix` with `@client.prefix` (the form field name stays `client[client_prefix]` for controller compatibility).
  - The edit form posts to `@action_url` (already set to `/clients/:slug`); the create form to `/clients/create`.
  - Guard nil `@client` in `_form.erb` (new-client case) — use `@client&.name`, etc. Example field:

```erb
<input type="text" name="client[name]" value="<%= @client&.name %>" class="w-full border rounded px-3 py-2">
```

  - In `edit.erb`, add a period-override select before the submit button:

```erb
<label class="block text-sm text-gray-600">Timesheet period (override)</label>
<select name="client[timesheet_period]" class="border rounded px-3 py-2">
  <option value="">Use business default (<%= current_business.defaults[:timesheet_period] %>)</option>
  <% %w[daily weekly monthly quarterly].each do |g| %>
    <option value="<%= g %>" <%= 'selected' if @client.timesheet_period_override == g %>><%= g.capitalize %></option>
  <% end %>
</select>
```

  - In `list.erb`, invoice links become `/invoices/<%= client.slug %>`.

- [ ] **Step 5: Run to verify it passes**

Run: `bundle exec rspec spec/requests/clients_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 6: Commit**

```bash
git add app/clients.rb views/clients spec/requests/clients_spec.rb
git commit -m "feat: rewrite Clients on the JSON store with slug routes

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: `Invoices` controller + views + PDF (embedded services, new URLs)

**Files:**
- Modify: `app/invoices.rb` (rewrite; keep the Prawn renderer)
- Modify: `views/invoices/list.erb`, `create.erb`, `edit.erb`, `_form.erb`, `_service_row.erb`, `view.erb`, `preview.erb`
- Modify: `views/admin/layout-default.erb` (Stimulus `removeService` no longer tracks `delete_services`)
- Test: `spec/requests/invoices_spec.rb` (rewrite)

**Interfaces:**
- Consumes: `current_business`, `Store::Client`, `Store::Invoice`, `Store::Business#resolve_logo`.
- Produces routes (under `/invoices`):
  - `GET /:client_key` (list), `GET /:client_key/create`, `POST /:client_key/create`,
    `GET /:client_key/:num/edit`, `POST /:client_key/:num` (update),
    `GET /:client_key/:num` (view), `GET /:client_key/:num/preview`, `GET /:client_key/:num/pdf`,
    `GET /:client_key/:num/approve|mark_sent|paid|delete`
  - helper `create_invoice_pdf(invoice, business)` writing to `invoice.pdf_path`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/invoices_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Invoices', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end

  around do |ex|
    with_temp_data_root do
      @biz = Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203')
      @client = @biz.create_client(name: 'Widgets Inc', prefix: 'WID', contact: 'J', email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203')
      ex.run
    end
  end

  before { post "/businesses/#{@biz.slug}/select" }

  def svc(i) { "invoice[services][#{i}][item]" => 'Dev', "invoice[services][#{i}][desc]" => 'x',
               "invoice[services][#{i}][service_date]" => '07/05/2026', "invoice[services][#{i}][qty]" => '2',
               "invoice[services][#{i}][cost]" => '125' } end

  it 'creates an invoice with an assigned number, a PDF, and serves it' do
    post '/invoices/widgets-inc/create', { 'invoice[num]' => '', 'invoice[invoice_date]' => '07/09/2026',
      'invoice[total_amount]' => '250', 'invoice[total_discount]' => '0', 'invoice[amount_paid]' => '0',
      'invoice[terms]' => 'Net 30', 'invoice[notes]' => 'thanks' }.merge(svc(0))
    inv = @client.invoices.first
    expect(inv.num).to eq('001')
    expect(inv.services.first.item).to eq('Dev')
    expect(inv.pdf_exists?).to be true

    get '/invoices/widgets-inc/001/pdf'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('application/pdf')
  end

  it '404s the pdf route when no PDF exists' do
    @client.create_invoice(services: []) # draft, no PDF
    get '/invoices/widgets-inc/001/pdf'
    expect(last_response.status).to eq(404)
  end

  it 'approves and marks paid' do
    @client.create_invoice(num: '001', services: [])
    get '/invoices/widgets-inc/001/approve'
    expect(@client.find_invoice('001').approved_on).not_to be_nil
    get '/invoices/widgets-inc/001/paid'
    expect(@client.find_invoice('001').get_status).to eq('paid')
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/invoices_spec.rb`
Expected: FAIL — old `Invoices` uses Sequel.

- [ ] **Step 3: Rewrite `app/invoices.rb`** (structure below; the Prawn body is ported verbatim from the current `create_invoice_pdf`, changing only the logo source and output path)

```ruby
require 'fileutils'

class Invoices < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { require_business! }

  helpers do
    def find_client!(key)
      c = current_business.find_client(key)
      halt(404) unless c
      c
    end

    def find_invoice!(client, num)
      i = client.find_invoice(num)
      halt(404) unless i
      i
    end

    def gather_invoice_data(d)
      { num: d[:num].to_s.empty? ? nil : d[:num],
        invoice_date: d[:invoice_date].to_s.empty? ? nil : Date.strptime(d[:invoice_date], '%m/%d/%Y'),
        total_amount: d[:total_amount].to_s.empty? ? 0.0 : d[:total_amount].gsub(/[^\d.]/, '').to_f,
        total_discount: d[:total_discount].to_s.empty? ? 0.0 : d[:total_discount].gsub(/[^\d.]/, '').to_f,
        amount_paid: d[:amount_paid].to_s.empty? ? 0.0 : d[:amount_paid].gsub(/[^\d.]/, '').to_f,
        terms: d[:terms], notes: d[:notes] }
    end

    def submitted_services(d)
      (d[:services] || {}).values.map do |s|
        { item: s[:item], desc: s[:desc],
          service_date: s[:service_date].to_s.empty? ? nil : Date.strptime(s[:service_date], '%m/%d/%Y'),
          qty: s[:qty], cost: s[:cost] }
      end
    end
  end

  get '/:client_key' do
    client = find_client!(params[:client_key])
    per_page = 20
    all = client.invoices
    @client = client
    @page = [params[:page].to_i, 1].max
    @total_pages = [(all.size.to_f / per_page).ceil, 1].max
    @invoices = all.slice((@page - 1) * per_page, per_page) || []
    @pagination_path = "/invoices/#{client.slug}"
    @page_title = "Invoices — #{client.name}"
    v :'invoices/list'
  end

  get '/:client_key/create' do
    @client = find_client!(params[:client_key])
    @invoice = Store::Invoice.new(@client, Store::Invoice.blank_data(''))
    @services = [Store::Service.new({})]
    @action_url = "/invoices/#{@client.slug}/create"
    @submit_value = 'Create Invoice'
    @page_title = "New Invoice — #{@client.name}"
    v :'invoices/create'
  end

  post '/:client_key/create' do
    client = find_client!(params[:client_key])
    data = gather_invoice_data(params[:invoice]).merge(services: submitted_services(params[:invoice]))
    data[:is_complete] = true
    invoice = client.create_invoice(data)
    create_invoice_pdf(invoice, current_business)
    flash[:success] = 'Invoice created successfully'
    redirect "/invoices/#{client.slug}"
  end

  get '/:client_key/:num/edit' do
    @client = find_client!(params[:client_key])
    @invoice = find_invoice!(@client, params[:num])
    @services = @invoice.services.empty? ? [Store::Service.new({})] : @invoice.services
    @action_url = "/invoices/#{@client.slug}/#{@invoice.num}"
    @submit_value = 'Update Invoice'
    @page_title = "Edit Invoice — #{@client.name}"
    v :'invoices/edit'
  end

  post '/:client_key/:num' do
    client = find_client!(params[:client_key])
    invoice = find_invoice!(client, params[:num])
    invoice.update(gather_invoice_data(params[:invoice]).merge(services: submitted_services(params[:invoice]), is_complete: true))
    create_invoice_pdf(invoice, current_business)
    flash[:success] = 'Invoice updated successfully'
    redirect "/invoices/#{client.slug}"
  end

  get '/:client_key/:num/approve' do
    client = find_client!(params[:client_key]); invoice = find_invoice!(client, params[:num])
    invoice.update(approved_on: Time.now) if invoice.approved_on.nil?
    flash[:success] = 'Invoice approved!'
    redirect "/invoices/#{client.slug}/#{invoice.num}"
  end

  get '/:client_key/:num/mark_sent' do
    client = find_client!(params[:client_key]); invoice = find_invoice!(client, params[:num])
    invoice.update(sent_at: Time.now) if invoice.sent_at.nil?
    flash[:success] = 'Invoice marked as sent!'
    redirect "/invoices/#{client.slug}/#{invoice.num}"
  end

  get '/:client_key/:num/paid' do
    client = find_client!(params[:client_key]); invoice = find_invoice!(client, params[:num])
    invoice.update(paid_at: Time.now) if invoice.paid_at.nil?
    flash[:success] = 'Invoice marked as paid!'
    redirect "/invoices/#{client.slug}/#{invoice.num}"
  end

  get '/:client_key/:num/delete' do
    client = find_client!(params[:client_key]); invoice = find_invoice!(client, params[:num])
    halt 403 unless invoice.deletable?
    invoice.soft_delete
    flash[:success] = 'Invoice deleted.'
    redirect "/invoices/#{client.slug}"
  end

  get '/:client_key/:num/pdf' do
    client = find_client!(params[:client_key]); invoice = find_invoice!(client, params[:num])
    halt 404 unless invoice.pdf_exists?
    send_file invoice.pdf_path, type: 'application/pdf', disposition: 'inline'
  end

  get '/:client_key/:num/preview' do
    @client = find_client!(params[:client_key])
    @invoice = find_invoice!(@client, params[:num])
    @company = current_business
    logo = current_business.resolve_logo
    @logo_url = logo ? logo[:web] : nil
    erb :'invoices/preview', layout: false
  end

  get '/:client_key/:num' do
    @client = find_client!(params[:client_key])
    @invoice = find_invoice!(@client, params[:num])
    @company = current_business
    @pdf_invoice_path = @invoice.pdf_exists? ? "/invoices/#{@client.slug}/#{@invoice.num}/pdf" : nil
    @page_title = "Invoice #{@client.prefix}-#{@invoice.num} — #{@client.name}"
    v :'invoices/view'
  end

  helpers do
    def create_invoice_pdf(invoice, business)
      Store::InvoicePdf.render(invoice, business, invoice.pdf_path)
    end
  end
end
```

- [ ] **Step 3b: Create `lib/store/invoice_pdf.rb`** (the Prawn renderer, shared by the controller and the sample script)

Add `require 'store/invoice_pdf'` to `lib/store.rb`. The body below is ported verbatim from the current `app/invoices.rb` `create_invoice_pdf` (lines 237–392); the only changes are `company.*` → `business.*` and `invoice.client.client_prefix` → `invoice.client.prefix`.

```ruby
# lib/store/invoice_pdf.rb
require 'prawn'
require 'prawn/table'

module Store
  module InvoicePdf
    module_function

    def render(invoice, business, path)
      FileUtils.mkdir_p(File.dirname(path))
      logo = business.resolve_logo
      logo_local = logo ? logo[:local] : nil

      Prawn::Document.generate(path) do |pdf|
        w     = pdf.bounds.width
        base  = 9
        small = 7
        lh    = 13
        gray  = '666666'
        lgray = 'aaaaaa'
        half  = w * 0.50

        pdf.font 'Helvetica'
        pdf.font_size base

        # ── HEADER ──
        header_top = pdf.cursor
        left_y     = header_top

        pdf.font('Helvetica', style: :bold) do
          pdf.text_box business.name.to_s, at: [0, left_y], width: half, size: 11
        end
        left_y -= 16
        pdf.fill_color gray
        [business.contact, business.street, business.city_state_zip, business.email].each do |line|
          next if line.to_s.strip.empty?
          pdf.text_box line.to_s, at: [0, left_y], width: half, size: base
          left_y -= lh
        end
        pdf.fill_color '000000'

        pdf.move_cursor_to header_top
        if logo_local && File.exist?(logo_local)
          pdf.image logo_local, fit: [200, 55], position: :right
          pdf.move_down 6
        end
        pdf.font('Helvetica', style: :bold) { pdf.text 'INVOICE', size: 22, align: :right }
        pdf.font('Helvetica', style: :bold) do
          pdf.text "#{invoice.client.prefix}-#{invoice.num}", size: base, align: :right
        end
        pdf.fill_color gray
        pdf.text invoice.formatted_invoice_date, size: base, align: :right
        pdf.fill_color '000000'
        pdf.move_down 8

        balance_w = 175
        pdf.table([['Balance Due', "$#{invoice.formatted_final_amount} USD"]], position: w - balance_w, width: balance_w) do
          style(row(0).columns(0..1), background_color: 'f5f5f5', border_color: 'e0e0e0',
                borders: [:top, :right, :bottom, :left], padding: [7, 8, 7, 8])
          style(column(0), font_style: :bold, size: small, text_color: lgray)
          style(column(1), font_style: :bold, size: 12, align: :right)
        end

        pdf.move_cursor_to [left_y, pdf.cursor].min - 16

        # ── BILL TO ──
        bill_top = pdf.cursor
        pdf.fill_color lgray
        pdf.font('Helvetica', style: :bold) { pdf.text_box 'BILL TO', at: [0, bill_top], size: small }
        pdf.fill_color '000000'
        bill_top -= 12

        pdf.font('Helvetica', style: :bold) do
          pdf.text_box invoice.client.name.to_s, at: [0, bill_top], size: base
        end
        bill_top -= lh

        pdf.fill_color gray
        [
          invoice.client.contact,
          "#{invoice.client.street} #{invoice.client.street2}".strip,
          "#{invoice.client.city}, #{invoice.client.state} #{invoice.client.zip}",
          invoice.client.email
        ].each do |line|
          next if line.to_s.gsub(/[\s,]/, '').empty?
          pdf.text_box line.to_s, at: [0, bill_top], width: half, size: base
          bill_top -= lh
        end
        pdf.fill_color '000000'

        pdf.move_cursor_to bill_top - 18

        # ── SERVICES ──
        service_data = [['Item', 'Description', 'Date', 'Unit Cost', 'Qty', 'Line Total']]
        invoice.services.each do |s|
          service_data << [s.item.to_s, s.desc.to_s, s.formatted_service_date,
                           "$#{s.formatted_cost}", s.qty.to_s, "$#{s.formatted_line_total}"]
        end

        pdf.table(service_data, width: w) do
          style(row(0..-1).columns(0..-1), padding: [5, 6, 5, 6], border_width: 0)
          style(row(0), background_color: 'f9f9f9', font_style: :bold, size: small, text_color: lgray)
          style(row(1..-1).columns(0..-1), borders: [:bottom], border_color: 'f2f2f2')
          style(column(2..-1), align: :right)
          style(column(0), width: 65)
          style(column(1), width: 200)
          style(column(2), width: 65)
        end

        pdf.move_down 16

        # ── TOTALS ──
        totals_w = 220
        totals_x = w - totals_w

        if invoice.total_discount.to_f > 0
          pdf.table([['Subtotal', "$#{invoice.formatted_total_amount}"],
                     ["Discount (#{invoice.formatted_discount_percentage}%)", "-$#{invoice.formatted_total_discount}"]], position: totals_x, width: totals_w) do
            style(row(0..-1).columns(0..-1), padding: [3, 6, 3, 6], borders: [], text_color: gray)
            style(column(1), align: :right)
          end
          pdf.table([['Invoice Total', "$#{invoice.formatted_discount_total_amount}"]], position: totals_x, width: totals_w) do
            style(row(0).columns(0..1), padding: [4, 6, 4, 6], borders: [:top], border_color: 'e8e8e8', font_style: :bold, text_color: '111111')
            style(column(1), align: :right)
          end
        else
          pdf.table([['Invoice Total', "$#{invoice.formatted_total_amount}"]], position: totals_x, width: totals_w) do
            style(row(0).columns(0..1), padding: [3, 6, 3, 6], borders: [], font_style: :bold, text_color: '111111')
            style(column(1), align: :right)
          end
        end

        if invoice.amount_paid.to_f > 0
          pdf.table([['Amount Paid', "-$#{invoice.formatted_amount_paid}"]], position: totals_x, width: totals_w) do
            style(row(0).columns(0..1), padding: [3, 6, 3, 6], borders: [], text_color: gray)
            style(column(1), align: :right)
          end
        end

        pdf.table([['Balance Due', "$#{invoice.formatted_final_amount} USD"]], position: totals_x, width: totals_w) do
          style(row(0).columns(0..1), background_color: 'f5f5f5', border_color: 'e5e5e5',
                borders: [:top, :right, :bottom, :left], padding: [7, 8, 7, 8])
          style(column(0), font_style: :bold)
          style(column(1), font_style: :bold, size: 12, align: :right)
        end

        pdf.move_down 24

        # ── FOOTER: Terms | Notes ──
        col_w    = (w - 20) / 2.0
        footer_y = pdf.cursor

        pdf.fill_color lgray
        pdf.font('Helvetica', style: :bold) { pdf.text_box 'Terms', at: [0, footer_y], size: small }
        pdf.fill_color '444444'
        pdf.text_box invoice.formatted_terms, at: [0, footer_y - 11], width: col_w, size: base

        pdf.fill_color lgray
        pdf.font('Helvetica', style: :bold) { pdf.text_box 'Notes', at: [col_w + 20, footer_y], size: small }
        pdf.fill_color '444444'
        pdf.text_box invoice.formatted_notes, at: [col_w + 20, footer_y - 11], width: col_w, size: base
        pdf.fill_color '000000'
      end
      path
    end
  end
end
```

- [ ] **Step 4: Update the invoice views.**
  - `views/invoices/_form.erb` and `_service_row.erb`: **remove** the hidden `invoice[services][i][service_id]` input and any `delete_services` inputs. Rows are now index-keyed only; the whole set is replaced on save. Keep the visible item/desc/date/qty/cost inputs, named `invoice[services][<index>][field]`. Also change the `_form.erb` header call `@invoice.formatted_invoice_num(@client)` to `@invoice.formatted_invoice_num` — Task 5 made that method 0-arg. Because both the create and edit routes now pass a blank `Store::Invoice` + `[Store::Service.new({})]` (not `nil`), `_form.erb`/`_service_row.erb` can call `@invoice.formatted_*` and `s.item`/`s.formatted_service_date`/etc. without nil guards, exactly as they did with the old `Invoice.new`/`[Service.new]`.
  - `views/admin/layout-default.erb`: in the Stimulus `removeService` handler, delete the block that pushes the removed row's id into a hidden `invoice[delete_services][]`; the handler now just removes the row element from the DOM.
  - `views/invoices/view.erb`: action links → `/invoices/<%= @client.slug %>/<%= @invoice.num %>/approve` (and `mark_sent`, `paid`, `delete`, `edit`, `preview`); the PDF button uses `@pdf_invoice_path` (already guarded by nil). Remove the "Send" (email) button entirely.
  - `views/invoices/list.erb`: view links → `/invoices/<%= @client.slug %>/<%= inv.num %>`; use `inv.get_status` and `STATUS_COLORS`.
  - `views/invoices/preview.erb`: the logo `<img src="<%= @logo_url %>">` now points at `/businesses/logo?v=…` via `@logo_url` (already set). Replace `@company.*` reads as needed (fields match `Business`).
  - `views/invoices/create.erb` / `edit.erb`: they render `_form` with `@services`; ensure the "add row" template still works with index-based names.

- [ ] **Step 5: Run to verify it passes**

Run: `bundle exec rspec spec/requests/invoices_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 6: Commit**

```bash
git add app/invoices.rb lib/store/invoice_pdf.rb lib/store.rb views/invoices views/admin/layout-default.erb spec/requests/invoices_spec.rb
git commit -m "feat: rewrite Invoices on the store — embedded services, data-dir PDFs, new URLs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: `Settings` controller + views

**Files:**
- Modify: `app/settings.rb` (rewrite)
- Modify: `views/settings/index.erb`
- Test: `spec/requests/settings_spec.rb`

**Interfaces:**
- Consumes: `current_business`, `Business#update`, `Business#save_logo`.
- Produces routes (under `/settings`): `GET /`, `POST /company`, `POST /logo`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/settings_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Settings', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end
  around do |ex|
    with_temp_data_root do
      @biz = Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203')
      ex.run
    end
  end
  before { post "/businesses/#{@biz.slug}/select" }

  it 'updates company info and the default timesheet period' do
    post '/settings/company', company: { name: 'Biz 2', contact: 'C2', email: 'b2@x.com',
                                         street: '9', city: 'CLT', state: 'NC', zip: '28204',
                                         timesheet_period: 'weekly', terms: 'Net 15', notes: 'ty' }
    b = Store::Business.find(@biz.slug)
    expect(b.name).to eq('Biz 2')
    expect(b.defaults[:timesheet_period]).to eq('weekly')
    expect(b.defaults[:terms]).to eq('Net 15')
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/settings_spec.rb`
Expected: FAIL — old `Settings` uses Sequel `Company`.

- [ ] **Step 3: Rewrite `app/settings.rb`**

```ruby
require 'fileutils'

class Settings < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { require_business! }

  get '/' do
    @business = current_business
    logo = @business.resolve_logo
    @logo_url = logo ? logo[:web] : nil
    @page_title = 'Settings'
    v :'settings/index'
  end

  post '/company' do
    p = params[:company]
    current_business.update(
      name: p[:name], contact: p[:contact], email: p[:email],
      street: p[:street], city: p[:city], state: p[:state], zip: p[:zip],
      defaults: { timesheet_period: p[:timesheet_period], terms: p[:terms], notes: p[:notes] }
    )
    flash[:success] = 'Company info saved.'
    redirect '/settings'
  end

  post '/logo' do
    upload = params[:logo]
    unless upload && upload[:filename] && !upload[:filename].empty?
      flash[:error] = 'Please select an image file.'
      redirect '/settings'
    end
    unless upload[:type].to_s.start_with?('image/')
      flash[:error] = 'Please upload a valid image file.'
      redirect '/settings'
    end
    current_business.save_logo(upload[:tempfile].path)
    flash[:success] = 'Logo updated.'
    redirect '/settings'
  end
end
```

- [ ] **Step 4: Update `views/settings/index.erb`**
  - The company form posts to `/settings/company`; fields read from `@business` (`@business.name`, `.contact`, `.email`, `.street`, `.city`, `.state`, `.zip`).
  - Add three fields to the company form: a `company[timesheet_period]` select (options daily/weekly/monthly/quarterly, current = `@business.defaults[:timesheet_period]`), and `company[terms]` / `company[notes]` text inputs (values from `@business.defaults[:terms]` / `[:notes]`).
  - The logo `<img>` uses `@logo_url` (served by `/businesses/logo`); the upload form posts to `/settings/logo` with `enctype="multipart/form-data"`.

```erb
<label class="block text-sm text-gray-600">Default timesheet period</label>
<select name="company[timesheet_period]" class="border rounded px-3 py-2">
  <% %w[daily weekly monthly quarterly].each do |g| %>
    <option value="<%= g %>" <%= 'selected' if @business.defaults[:timesheet_period] == g %>><%= g.capitalize %></option>
  <% end %>
</select>
```

- [ ] **Step 5: Run to verify it passes**

Run: `bundle exec rspec spec/requests/settings_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/settings.rb views/settings/index.erb spec/requests/settings_spec.rb
git commit -m "feat: rewrite Settings to edit the active business config + defaults

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: `Timesheets` controller + views (period navigation + roll-up)

**Files:**
- Modify: `app/timesheets.rb` (rewrite)
- Modify: `views/timesheets/index.erb`, `views/timesheets/show.erb`, `views/timesheets/_row.erb`
- Test: `spec/requests/timesheets_spec.rb`

**Interfaces:**
- Consumes: `current_business`, `Client#timesheet_period`, `Client#timesheet_summary`, `TimesheetPeriod#apply/#create_invoice/#prev_key/#next_key`.
- Produces routes (under `/timesheets`):
  - `GET /` (client list + summaries), `GET /:client_key?period=KEY` (one period),
    `POST /:client_key?period=KEY` (bulk save), `POST /:client_key/invoice?period=KEY` (roll-up)

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/timesheets_spec.rb
require 'spec_helper'
require 'rack/test'

RSpec.describe 'Timesheets', type: :request do
  include Rack::Test::Methods
  def app
    built = Rack::Builder.parse_file(File.expand_path('../../config.ru', __dir__))
    built.is_a?(Array) ? built.first : built   # Rack 2 returns [app, opts]; Rack 3 returns app
  end
  around do |ex|
    with_temp_data_root do
      @biz = Store::Business.create(name: 'Biz', contact: 'C', email: 'b@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203')
      @client = @biz.create_client(name: 'Widgets Inc', prefix: 'WID', contact: 'J', email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203')
      ex.run
    end
  end
  before { post "/businesses/#{@biz.slug}/select" }

  it 'saves entries into a period and rolls them into an invoice' do
    post '/timesheets/widgets-inc?period=2026-07',
         'entries[0][item]' => 'Dev', 'entries[0][desc]' => 'x',
         'entries[0][service_date]' => '07/05/2026', 'entries[0][qty]' => '2', 'entries[0][cost]' => '125'
    expect(@client.timesheet_period('2026-07').entries.size).to eq(1)

    post '/timesheets/widgets-inc/invoice?period=2026-07'
    expect(@client.invoices.size).to eq(1)
    expect(@client.timesheet_summary).to eq(total: 1, uninvoiced: 0)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/timesheets_spec.rb`
Expected: FAIL — old `Timesheets` uses Sequel.

- [ ] **Step 3: Rewrite `app/timesheets.rb`**

```ruby
class Timesheets < SimplyBase
  set :layout_default, :'admin/layout-default'

  before { require_business! }

  helpers do
    def parse_rows(entries)
      (entries || {}).values.map do |e|
        { id: e[:id], item: e[:item], desc: e[:desc],
          service_date: e[:service_date].to_s.empty? ? nil : (Date.strptime(e[:service_date], '%m/%d/%Y') rescue nil),
          qty: e[:qty], cost: e[:cost] }
      end
    end
  end

  get '/' do
    @clients = current_business.clients
    @summaries = @clients.to_h { |c| [c.slug, c.timesheet_summary] }
    @page_title = 'Timesheets'
    v :'timesheets/index'
  end

  get '/:client_key' do
    @client = current_business.find_client(params[:client_key])
    halt 404 unless @client
    @period = @client.timesheet_period(params[:period])
    @entries = @period.entries
    @page_title = "Timesheets — #{@client.name}"
    v :'timesheets/show'
  end

  post '/:client_key' do
    client = current_business.find_client(params[:client_key])
    halt 404 unless client
    period = client.timesheet_period(params[:period])
    period.apply(rows: parse_rows(params[:entries]), deletes: params[:delete_entries] || [])
    flash[:success] = 'Timesheet saved.'
    redirect "/timesheets/#{client.slug}?period=#{period.key}"
  end

  post '/:client_key/invoice' do
    client = current_business.find_client(params[:client_key])
    halt 404 unless client
    period = client.timesheet_period(params[:period])
    invoice = period.create_invoice
    if invoice
      flash[:success] = "Draft invoice #{client.prefix}-#{invoice.num} created."
      redirect "/invoices/#{client.slug}/#{invoice.num}/edit"
    else
      flash[:error] = 'No un-invoiced entries in this period.'
      redirect "/timesheets/#{client.slug}?period=#{period.key}"
    end
  end
end
```

- [ ] **Step 4: Update the timesheet views.**
  - `views/timesheets/index.erb`: iterate `@clients`; for each use `client.slug` and `@summaries[client.slug]` for the `total`/`uninvoiced` counts; link to `/timesheets/<%= client.slug %>`.
  - `views/timesheets/show.erb`: add a period header with prev/next links —
    `‹ /timesheets/<%= @client.slug %>?period=<%= @period.prev_key %>`, the current `@period.key`, and next; render the `@entries` rows with `_row`; the save form posts to `/timesheets/<%= @client.slug %>?period=<%= @period.key %>`. Add a "Create invoice from this period" form posting to `/timesheets/<%= @client.slug %>/invoice?period=<%= @period.key %>`, shown only when `@entries.any? { |e| !e[:invoiced] }`.
  - `views/timesheets/_row.erb`: bind to hash keys (`entry[:id]`, `entry[:item]`, `entry[:desc]`, `entry[:service_date]` → format `%m/%d/%Y`, `entry[:qty]`, `entry[:cost]`); when `entry[:invoiced]`, render the row read-only (disabled inputs, no delete). Field names stay `entries[<index>][field]` with a hidden `entries[<index>][id]`.

```erb
<!-- views/timesheets/show.erb — period nav + roll-up button -->
<div class="flex items-center justify-between mb-4">
  <a href="/timesheets/<%= @client.slug %>?period=<%= @period.prev_key %>">‹ Prev</a>
  <span class="font-medium"><%= @period.key %></span>
  <a href="/timesheets/<%= @client.slug %>?period=<%= @period.next_key %>">Next ›</a>
</div>
<% if @entries.any? { |e| !e[:invoiced] } %>
  <form method="post" action="/timesheets/<%= @client.slug %>/invoice?period=<%= @period.key %>" class="mb-4">
    <button class="bg-green-600 text-white px-3 py-2 rounded" type="submit">Create invoice from this period</button>
  </form>
<% end %>
```

- [ ] **Step 5: Run to verify it passes**

Run: `bundle exec rspec spec/requests/timesheets_spec.rb`
Expected: PASS.

- [ ] **Step 6: Run the full request suite**

Run: `bundle exec rspec spec/requests`
Expected: PASS (boot, businesses, clients, invoices, settings, timesheets).

- [ ] **Step 7: Commit**

```bash
git add app/timesheets.rb views/timesheets spec/requests/timesheets_spec.rb
git commit -m "feat: rewrite Timesheets with period navigation and roll-into-invoice

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: One-time SQLite → JSON export script

**Files:**
- Create: `scripts/export_to_json.rb`
- Test: `spec/scripts/export_to_json_spec.rb`

**Interfaces:**
- Consumes: the current Sequel models (`models/models.rb`) — still present until Task 14 — and `Store`.
- Produces: a populated `data/<business>/…` tree from an existing SQLite DB.

**Note:** This task runs while Sequel is still installed. It is the last consumer of the DB.

- [ ] **Step 1: Write the failing test** (builds a tiny SQLite DB via Sequel, exports, asserts the JSON tree)

```ruby
# spec/scripts/export_to_json_spec.rb
require 'spec_helper'
require 'sequel'

RSpec.describe 'export_to_json' do
  around { |ex| with_temp_data_root { ex.run } }

  it 'exports company, clients, invoices+services and timesheets' do
    db = Sequel.sqlite
    db.create_table(:companies) { primary_key :id; String :name; String :contact; String :email; String :street; String :city; String :state; String :zip }
    db.create_table(:clients) { primary_key :id; String :client_key; String :client_prefix; String :name; String :contact; String :email; String :street; String :street2; String :city; String :state; String :zip; DateTime :deleted_at }
    db.create_table(:invoices) { primary_key :id; Integer :client_id; String :num; DateTime :invoice_date; Float :total_amount; Float :total_discount; Float :amount_paid; TrueClass :is_complete; String :terms; String :notes; DateTime :approved_on; DateTime :sent_at; DateTime :paid_at; DateTime :deleted_at }
    db.create_table(:services) { primary_key :id; Integer :invoice_id; String :item; String :desc; DateTime :service_date; Float :qty; Float :cost }
    db.create_table(:timesheets) { primary_key :id; Integer :client_id; Integer :invoice_id; String :item; String :desc; DateTime :service_date; Float :qty; Float :cost; TrueClass :invoiced }
    db[:companies].insert(name: 'Acme LLC', contact: 'Me', email: 'a@x.com', street: '1', city: 'CLT', state: 'NC', zip: '28203')
    cid = db[:clients].insert(client_key: 'widgets-inc', client_prefix: 'WID', name: 'Widgets Inc', contact: 'J', email: 'j@w.com', street: '2', street2: '', city: 'CLT', state: 'NC', zip: '28203')
    iid = db[:invoices].insert(client_id: cid, num: '001', invoice_date: Time.new(2026,7,9), total_amount: 250.0, total_discount: 0, amount_paid: 0, is_complete: true, terms: 'Net 30', notes: 'ty')
    db[:services].insert(invoice_id: iid, item: 'Dev', desc: 'x', service_date: Time.new(2026,7,5), qty: 2, cost: 125)
    db[:timesheets].insert(client_id: cid, invoice_id: iid, item: 'Dev', desc: 'x', service_date: Time.new(2026,7,5), qty: 2, cost: 125, invoiced: true)

    load File.expand_path('../../scripts/export_to_json.rb', __dir__)
    ExportToJson.run(db, Store.data_root)

    biz = Store::Business.all.first
    expect(biz.name).to eq('Acme LLC')
    client = biz.find_client('widgets-inc')
    expect(client.prefix).to eq('WID')
    inv = client.find_invoice('001')
    expect(inv.services.first.item).to eq('Dev')
    ts = client.timesheet_period('2026-07').entries.first
    expect(ts[:invoiced]).to be true
    expect(ts[:invoice_num]).to eq('001')
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/scripts/export_to_json_spec.rb`
Expected: FAIL — `uninitialized constant ExportToJson`.

- [ ] **Step 3: Implement `scripts/export_to_json.rb`** as a module with a testable `run(db, data_root)` plus a CLI tail

```ruby
# scripts/export_to_json.rb
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'store'

module ExportToJson
  module_function

  def run(db, data_root)
    Store.data_root = data_root
    co = db[:companies].first
    biz = Store::Business.create(
      { name: co[:name], contact: co[:contact], email: co[:email],
        street: co[:street], city: co[:city], state: co[:state], zip: co[:zip] },
      legacy_logo
    )

    db[:clients].each do |c|
      client = build_client(biz, c)
      export_invoices(db, client, c[:id])
      export_timesheets(db, client, c[:id])
    end
  end

  # Migrate the existing single logo (spec Section 7 step 2). Returns a path or nil.
  def legacy_logo
    %w[public/client-assets/logo.png public/css/images/logo.png]
      .map { |p| File.join(Store::APP_ROOT, p) }
      .find { |p| File.exist?(p) }
  end

  def build_client(biz, c)
    # write client.json directly to preserve the existing slug (client_key)
    data = { slug: c[:client_key], prefix: c[:client_prefix], name: c[:name],
             contact: c[:contact], email: c[:email], street: c[:street], street2: c[:street2],
             city: c[:city], state: c[:state], zip: c[:zip], timesheet_period: nil,
             created_at: Store.now_iso, updated_at: Store.now_iso }
    dest_dir = c[:deleted_at] ? File.join(biz.clients_dir, 'archive', c[:client_key]) : File.join(biz.clients_dir, c[:client_key])
    Store.write_json(File.join(dest_dir, 'client.json'), data)
    Store::Client.new(biz, data)
  end

  def export_invoices(db, client, client_id)
    db[:invoices].where(client_id: client_id).each do |i|
      services = db[:services].where(invoice_id: i[:id]).map do |s|
        Store::Service.new(item: s[:item], desc: s[:desc], service_date: iso_date(s[:service_date]), qty: s[:qty], cost: s[:cost]).to_h
      end
      data = { num: i[:num], invoice_date: iso_date(i[:invoice_date]),
               total_amount: i[:total_amount].to_f, total_discount: i[:total_discount].to_f,
               amount_paid: i[:amount_paid].to_f, is_complete: i[:is_complete] ? true : false,
               terms: i[:terms], notes: i[:notes],
               approved_on: iso_time(i[:approved_on]), sent_at: iso_time(i[:sent_at]), paid_at: iso_time(i[:paid_at]),
               services: services, created_at: Store.now_iso, updated_at: Store.now_iso }
      sub = i[:deleted_at] ? 'archive/' : ''
      Store.write_json(File.join(client.invoices_dir, "#{sub}#{i[:num]}.json"), data)
      copy_pdf(client, i[:num])
    end
  end

  def export_timesheets(db, client, client_id)
    db[:timesheets].where(client_id: client_id).each do |t|
      date = iso_date(t[:service_date]) || Date.today.strftime('%Y-%m-%d')
      key = Store::TimesheetPeriod.key_for(date, 'monthly')
      inv_num = t[:invoice_id] ? db[:invoices].where(id: t[:invoice_id]).get(:num) : nil
      entry = { id: SecureRandom.hex(3), item: t[:item], desc: t[:desc], service_date: date,
                qty: t[:qty].to_f, cost: t[:cost].to_f, invoiced: t[:invoiced] ? true : false,
                invoice_num: inv_num, created_at: Store.now_iso, updated_at: Store.now_iso }
      path = File.join(client.timesheets_dir, "#{key}.json")
      data = Store.read_json(path) || { period: key, granularity: 'monthly', entries: [] }
      (data[:entries] ||= []) << entry
      Store.write_json(path, data)
    end
  end

  def copy_pdf(client, num)
    legacy = File.join(Store::APP_ROOT, 'public', 'pdfs', client.slug, "#{client.prefix}-#{num}.pdf")
    if File.exist?(legacy)
      FileUtils.mkdir_p(client.invoices_dir)
      FileUtils.cp(legacy, File.join(client.invoices_dir, "#{client.prefix}-#{num}.pdf"))
    else
      warn "  (no PDF for #{client.slug} #{num})"
    end
  end

  def iso_date(v) = v.nil? ? nil : (v.respond_to?(:strftime) ? v.strftime('%Y-%m-%d') : Date.parse(v.to_s).strftime('%Y-%m-%d'))
  def iso_time(v) = v.nil? ? nil : (v.respond_to?(:strftime) ? v.getutc.strftime('%Y-%m-%dT%H:%M:%SZ') : v.to_s)
end

if $PROGRAM_NAME == __FILE__
  require 'dotenv'; Dotenv.load
  require 'sequel'
  db = Sequel.connect(ENV.fetch('DATABASE_URL'))
  ExportToJson.run(db, ENV.fetch('DATA_DIR', File.expand_path('../data', __dir__)))
  puts "\n✓ Export complete → #{ENV.fetch('DATA_DIR', 'data/')}"
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/scripts/export_to_json_spec.rb`
Expected: PASS.

- [ ] **Step 5: Run the real export (if a DB exists)**

```bash
bundle exec ruby scripts/export_to_json.rb   # reads DATABASE_URL, writes data/
```
Expected: a populated `data/<slug>/…` tree. Spot-check with `/preview` or by booting the app.

- [ ] **Step 6: Commit**

```bash
git add scripts/export_to_json.rb spec/scripts/export_to_json_spec.rb
git commit -m "feat: one-time SQLite -> JSON export script

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: Delete dead code (auth, email, unused models, DB) + fix sample scripts

**Files:**
- Delete: `app/auth.rb`, `lib/session_auth.rb`, `models/user.rb`, `models/models.rb`, `lib/mailer.rb`, `lib/action_mailer/`, `lib/app/mailman.rb`, `scripts/send_approve_invoices.rb`, `db/migrations/`, `db/migrate.rb`, `db/seeds.rb`, `db/load_json.rb`, `views/auth/`, `views/admin/layout-login.erb`, `views/invoices/html_email.erb`, `views/invoices/text_email.erb`, `spec/requests/auth_spec.rb`, `spec/models/user_spec.rb`, `spec/models/invoice_spec.rb` (Sequel-based; replaced by `spec/store/invoice_spec.rb`)
- Modify: `scripts/generate_invoice_pdf.rb`, `scripts/generate_invoice_screenshot.rb`

- [ ] **Step 1: Delete the dead files**

```bash
git rm -r app/auth.rb app/admin.rb lib/session_auth.rb models/user.rb models/models.rb \
  lib/mailer.rb lib/action_mailer lib/app/mailman.rb scripts/send_approve_invoices.rb \
  db/migrations db/migrate.rb db/seeds.rb db/load_json.rb \
  views/auth views/admin/layout-login.erb views/invoices/html_email.erb views/invoices/text_email.erb \
  spec/requests/auth_spec.rb spec/models/user_spec.rb spec/models/invoice_spec.rb
```

`app/admin.rb` is safe to delete: it is superseded by `Dashboard` (Task 7) and only the old `config.ru` referenced it. The kept `views/admin/*` (layout, home, error, not_found) stay — only `layout-login.erb` is removed.

- [ ] **Step 1b: Rewrite `spec/spec_helper.rb`** — the original still connects Sequel, runs migrations, requires `session_auth`/`mailer`/`bcrypt`/the old models/controllers, and truncates DB tables in a `before(:each)`. All of that breaks once the files/gems are gone. Replace the whole file with the store-only version (this supersedes the append from Task 1):

```ruby
# spec/spec_helper.rb
require 'tmpdir'
require 'fileutils'
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'store'

module DataRootHelper
  def with_temp_data_root
    dir = Dir.mktmpdir('simply-suite-spec')
    prev = Store.instance_variable_get(:@data_root)
    Store.data_root = dir
    yield
  ensure
    Store.instance_variable_set(:@data_root, prev)
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end
end

RSpec.configure do |c|
  c.include DataRootHelper
  c.expect_with(:rspec) { |e| e.syntax = :expect }
end
```

- [ ] **Step 2: Rewrite `scripts/generate_invoice_pdf.rb`** — build an in-memory business + client + invoice via the store (temp `DATA_DIR`) and render with `Store::InvoicePdf.render` (created in Task 10 Step 3b), dropping all `require 'session_auth'`/`'mailer'`, the DB seeding, and the stale 4-arg `create_invoice_pdf` call:

```ruby
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'store'
require 'tmpdir'
Store.data_root = Dir.mktmpdir('sample')
biz = Store::Business.create(name: 'Your Company, LLC', contact: 'Your Name', email: 'billing@you.com',
                             street: '123 Main St', city: 'Charlotte', state: 'NC', zip: '28203')
client = biz.create_client(name: 'Acme Corporation', prefix: 'ACM', contact: 'Jane', email: 'jane@acme.com',
                           street: '456 Client Ave', street2: '', city: 'Charlotte', state: 'NC', zip: '28203')
inv = client.create_invoice(invoice_date: '2026-07-09', total_amount: 4750.0, terms: 'Net 30 days', notes: 'Thank you',
  services: [{ item: 'Strategy', desc: 'Digital strategy & brand audit', service_date: '2026-07-01', qty: 1, cost: 1500 }])
out = File.expand_path('../docs/sample-invoice.pdf', __dir__)
Store::InvoicePdf.render(inv, biz, out)
puts "Wrote #{out}"
```

- [ ] **Step 3: Rewrite `scripts/generate_invoice_screenshot.rb`** to drop the `User`/`/login` flow and `require 'session_auth'`, build a temp business/client/invoice via the store, boot the app pointed at that `DATA_DIR`, and navigate to the new URL `/invoices/<slug>/<num>` (not the removed `/invoices/view/:id`). Remove the DB setup/teardown.

- [ ] **Step 4: Run the full suite + boot smoke test**

```bash
bundle exec rspec
bundle exec ruby -e "require './config.ru'" 2>&1 | head   # loads without Sequel/mail
```
Expected: specs PASS; no `LoadError` for sequel/mail/bcrypt/session_auth.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: delete auth, email, unused models, and DB code; fix sample scripts

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: Prune dependencies + docs + env + gitignore

**Files:**
- Modify: `Gemfile` (+ `Gemfile.lock` via bundle)
- Modify: `.env.example`, `.gitignore`, `Procfile`, `README.md`

- [ ] **Step 1: Edit `Gemfile`** — remove `sequel`, `sqlite3`, `mysql2`, `mail`, `bcrypt`. Keep `sinatra`, `puma`, `prawn`, `prawn-table`, `dotenv`, `sinatra-contrib`, the flash gem, and the `:test` group (`rspec`, `rack-test`).

- [ ] **Step 2: Run bundle**

```bash
bundle install
```
Expected: resolves without the removed gems; `Gemfile.lock` updated.

- [ ] **Step 3: Edit `.gitignore`** — add `data/`. Remove now-vestigial `public/pdfs/` and `public/client-assets/*` rules (or leave them; PDFs no longer go there). Keep `.env`, `tailwindcss`, `public/css/tailwind.css`.

- [ ] **Step 4: Edit `.env.example`** — remove `DATABASE_URL` and all `SMTP_*`; keep `SESSION_SECRET`; add a commented `# DATA_DIR=./data`.

- [ ] **Step 5: Edit `Procfile`** — keep the puma + Tailwind processes; remove anything referencing the DB or mail. (The current Procfile only starts puma + Tailwind, so likely no change — verify.)

- [ ] **Step 6: Rewrite the relevant `README.md` sections** — remove "Database"/migrations, SMTP/email, and the "Batch invoice sending (cron)" section and the standalone JSON-PDF DB steps. Add:
  - a "Data" section describing the `data/<business>/…` layout and `DATA_DIR`;
  - onboarding ("first run creates or selects a business at `/businesses`");
  - update the Setup steps (no migrations, no seed user); update the Routes table to the new URLs;
  - document the one-time `scripts/export_to_json.rb` migration and the post-migration cleanup (delete `public/pdfs/*` and `public/client-assets/logo.png`).

- [ ] **Step 7: Post-migration cleanup (documented, after verifying the export)**

```bash
rm -rf public/pdfs/*        # PDFs now live in data/<business>/clients/<slug>/invoices/
rm -f public/client-assets/logo.png
```

- [ ] **Step 8: Final verification**

```bash
bundle exec rspec
./tailwindcss -i public/css/input.css -o public/css/tailwind.css
bundle exec puma -p 9393   # visit http://localhost:9393 -> /businesses (onboarding or list)
```
Expected: specs green; app boots; onboarding/switcher works; create a client, an invoice (PDF renders + downloads), a timesheet period, and roll it into an invoice.

- [ ] **Step 9: Commit**

```bash
git add Gemfile Gemfile.lock .env.example .gitignore Procfile README.md
git commit -m "chore: drop DB/mail/bcrypt gems; document JSON data store and onboarding

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Notes on ordering & risk

- Tasks 1–6 build a fully unit-tested library with **no** app or DB coupling — safe to land incrementally.
- Task 7 is the cutover: after it, the app boots on the store. Tasks 8–12 restore each feature with request specs.
- Task 13 (export) must run **before** Task 14/15 delete Sequel and its gems — it is the DB's last reader.
- The Prawn renderer is ported verbatim (Task 10 / optional `InvoicePdf` extraction in Task 14); only the logo source and output path change. Do not rewrite the PDF layout.
- Slugs are immutable: none of the `#update` methods change a slug or move a directory.
