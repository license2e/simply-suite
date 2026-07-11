Sequel.migration do
  up do
    create_table(:timesheets) do
      primary_key :id
      foreign_key :client_id, :clients, null: false
      foreign_key :invoice_id, :invoices
      String   :item
      String   :desc
      DateTime :service_date
      Float    :qty
      Float    :cost
      TrueClass :invoiced, default: false
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down { drop_table(:timesheets) }
end
