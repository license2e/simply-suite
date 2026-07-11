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
