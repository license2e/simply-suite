Sequel.migration do
  up do
    add_column :clients,  :deleted_at, DateTime
    add_column :invoices, :deleted_at, DateTime
  end

  down do
    drop_column :clients,  :deleted_at
    drop_column :invoices, :deleted_at
  end
end
