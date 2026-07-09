require 'spec_helper'

RSpec.describe Invoice do
  let(:client) do
    c = Client.new; c.title = 'Spec Corp'; c.client_prefix = 'SPC'
    c.contact = 'Alice'; c.email = 'a@spec.com'; c.street = '1 St'
    c.city = 'City'; c.state = 'NC'; c.zip = '00000'; c.save; c
  end

  let(:invoice) do
    Invoice.create(
      client: client, num: '001', invoice_date: Time.now,
      total_amount: 1000.0, total_discount: 100.0, amount_paid: 200.0,
      is_complete: true, created_at: Time.now, updated_at: Time.now
    )
  end

  describe '#get_status' do
    it 'returns draft when not sent or approved' do
      expect(invoice.get_status).to eq('draft')
    end

    it 'returns approved when approved_on is set' do
      invoice.update(approved_on: Time.now)
      expect(invoice.get_status).to eq('approved')
    end

    it 'returns sent when sent_at is set' do
      invoice.update(sent_at: Time.now)
      expect(invoice.get_status).to eq('sent')
    end

    it 'returns paid when paid_at is set' do
      invoice.update(paid_at: Time.now)
      expect(invoice.get_status).to eq('paid')
    end
  end

  describe '#formatted_final_amount' do
    it 'calculates balance correctly' do
      expect(invoice.formatted_final_amount).to eq('700.00')
    end
  end

  describe '#editable?' do
    it 'returns true when not sent' do
      expect(invoice.editable?).to be true
    end

    it 'returns false when sent' do
      invoice.update(sent_at: Time.now)
      expect(invoice.editable?).to be false
    end
  end
end
