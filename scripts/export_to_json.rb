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
      archive_client(biz, client) if c[:deleted_at]
    end
  end

  # Migrate the existing single logo (spec Section 7 step 2). Returns a path or nil.
  def legacy_logo
    %w[public/client-assets/logo.png public/css/images/logo.png]
      .map { |p| File.join(Store::APP_ROOT, p) }
      .find { |p| File.exist?(p) }
  end

  def build_client(biz, c)
    # write client.json directly to preserve the existing slug (client_key).
    # Always write to the live path first — invoices/timesheets are exported
    # underneath it, then the whole tree is relocated to archive/ at once
    # (see archive_client) so nothing ends up split across two locations.
    data = { slug: c[:client_key], prefix: c[:client_prefix], name: c[:name],
             contact: c[:contact], email: c[:email], street: c[:street], street2: c[:street2],
             city: c[:city], state: c[:state], zip: c[:zip], timesheet_period: nil,
             created_at: Store.now_iso, updated_at: Store.now_iso }
    client = Store::Client.new(biz, data)
    Store.write_json(File.join(client.dir, 'client.json'), data)
    client
  end

  # Soft-deleted clients: relocate the whole client tree (client.json +
  # invoices/ + timesheets/) into clients/archive/<slug> in one move, mirroring
  # Store::Client#soft_delete's directory move (minus unbill_timesheets — this
  # is a raw historical copy, not a live delete, so invoiced/invoice_num on
  # timesheet entries are preserved exactly as recorded in the SQL DB).
  def archive_client(biz, client)
    archive_dir = File.join(biz.clients_dir, 'archive', client.slug)
    FileUtils.rm_rf(archive_dir)
    Store.move(client.dir, archive_dir)
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
      copy_pdf(client, i[:num], sub)
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

  def copy_pdf(client, num, sub = '')
    legacy = File.join(Store::APP_ROOT, 'public', 'pdfs', client.slug, "#{client.prefix}-#{num}.pdf")
    if File.exist?(legacy)
      dest = File.join(client.invoices_dir, "#{sub}#{client.prefix}-#{num}.pdf")
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(legacy, dest)
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
