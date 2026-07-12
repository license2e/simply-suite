# scripts/verify_timesheet_paste.rb — headless-Chrome wiring check for paste-import.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'store'
require 'tmpdir'
require 'rack'
require 'puma'
require 'puma/configuration'
require 'puma/launcher'
require 'net/http'
require 'ferrum'

PORT = 9466
Store.data_root = Dir.mktmpdir('paste-verify')
biz = Store::Business.create(name: 'Verify Co', contact: 'C', email: 'v@x.com',
                             street: '1', city: 'CLT', state: 'NC', zip: '28203')
client = biz.create_client(name: 'Paste Client', prefix: 'PC', contact: 'x', email: 'p@x.com',
                           street: '1', street2: '', city: 'CLT', state: 'NC', zip: '28203')
client.update(default_rate: '150')

ENV['RACK_ENV'] = 'development'
ENV['DATA_DIR'] = Store.data_root
app = Rack::Builder.parse_file(File.expand_path('../config.ru', __dir__))
app = app.first if app.is_a?(Array)
conf = Puma::Configuration.new { |c| c.bind "tcp://127.0.0.1:#{PORT}"; c.app app; c.silence_single_worker_warning rescue nil }
launcher = Puma::Launcher.new(conf)
Thread.new { launcher.run }
# wait for boot
20.times { (Net::HTTP.get_response(URI("http://127.0.0.1:#{PORT}/businesses")) rescue nil) && break; sleep 0.25 }

tsv = "Date\tItem\tDescription\tQty\tRate\n7/5/2026\tDev\tBuild API\t3\t$1,250.00\n2026-07-06\tDesign\tMockups\t2\t100\n7/7/2026\tSupport\tEmail\t1\t"
browser = Ferrum::Browser.new(headless: true, browser_options: { 'no-sandbox': nil }, timeout: 20)
begin
  browser.goto("http://127.0.0.1:#{PORT}/businesses")
  browser.at_css("form[action=\"/businesses/#{biz.slug}/select\"] button")&.click
  browser.network.wait_for_idle rescue nil
  browser.goto("http://127.0.0.1:#{PORT}/timesheets/#{client.slug}")
  sleep 0.7
  browser.execute(<<~JS)
    const form = document.querySelector('form[data-timesheet-target="form"]');
    const dt = new DataTransfer();
    dt.setData('text', #{tsv.dump});
    form.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
  JS
  sleep 0.4
  rows = browser.evaluate(<<~JS)
    Array.from(document.querySelectorAll('tbody [data-ts-row]')).map(r => ({
      date: r.querySelector('[name$="[service_date]"]')?.value,
      item: r.querySelector('[name$="[item]"]')?.value,
      desc: r.querySelector('[name$="[desc]"]')?.value,
      qty:  r.querySelector('[name$="[qty]"]')?.value,
      cost: r.querySelector('[name$="[cost]"]')?.value,
    }))
  JS
  require 'pp'; pp rows
  ok = rows.length == 3 &&
       rows[0].values_at('date','item','desc','qty','cost') == ['07/05/2026','Dev','Build API','3','1250.00'] &&
       rows[1].values_at('date','item','desc','qty','cost') == ['07/06/2026','Design','Mockups','2','100'] &&
       rows[2].values_at('date','item','desc','qty','cost') == ['07/07/2026','Support','Email','1','150.00']
  puts(ok ? 'RESULT: PASS — pasted range expanded into normalized rows ✓' : 'RESULT: FAIL')
  exit(ok ? 0 : 1)
ensure
  browser.quit
  launcher.stop rescue nil
end
