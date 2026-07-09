Sequel.migration do
  up do
    create_table(:companies) do
      primary_key :id
      String :name, null: false
      String :contact
      String :email
      String :street
      String :city
      String :state
      String :zip
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down { drop_table(:companies) }
end
