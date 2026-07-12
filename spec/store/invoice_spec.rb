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

  it 'raises DuplicateInvoiceNumber instead of overwriting an existing invoice' do
    client.create_invoice(num: '001', services: [])
    expect do
      client.create_invoice(num: '001', services: [])
    end.to raise_error(Store::DuplicateInvoiceNumber)
  end

  it 'next_num skips archived numbers so a deleted draft cannot be reused' do
    inv = client.create_invoice(num: '001', services: [])
    inv.soft_delete
    expect(client.next_num).to eq('002')
  end

  it 'formatted_discount_percentage is 0.0 when total_amount is zero' do
    inv = client.create_invoice(num: '001', total_amount: 0, total_discount: 50, services: [])
    expect(inv.formatted_discount_percentage).to eq('0.0')
  end

  it 'is deletable as a draft but not once sent' do
    inv = client.create_invoice(services: [])
    expect(inv.deletable?).to be true
    inv.update(sent_at: Time.now)
    expect(client.find_invoice(inv.num).deletable?).to be false
  end
end
