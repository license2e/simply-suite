Sequel.migration do
  up do
    create_table(:invoices) do
      primary_key :id
      foreign_key :client_id, :clients, null: false
      String :num
      DateTime :invoice_date
      Float :total_amount, default: 0.0
      Float :total_discount, default: 0.0
      Float :amount_paid, default: 0.0
      TrueClass :is_complete, default: false
      Text :terms
      Text :notes
      DateTime :approved_on
      DateTime :sent_at
      DateTime :paid_at
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down { drop_table(:invoices) }
end
