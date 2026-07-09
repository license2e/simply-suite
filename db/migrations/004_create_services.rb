Sequel.migration do
  up do
    create_table(:services) do
      primary_key :id
      foreign_key :invoice_id, :invoices, null: false
      String :item
      String :desc
      DateTime :service_date
      Integer :qty
      Float :cost
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down { drop_table(:services) }
end
