Sequel.migration do
  up do
    create_table(:clients) do
      primary_key :id
      String :client_key, null: false, unique: true
      String :client_prefix, null: false, size: 12
      String :name, null: false
      String :contact, null: false
      String :email, null: false
      String :street, null: false
      String :street2
      String :city, null: false
      String :state, null: false
      String :zip, null: false
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down { drop_table(:clients) }
end
