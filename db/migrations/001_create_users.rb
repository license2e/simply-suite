Sequel.migration do
  up do
    create_table(:users) do
      primary_key :id
      String :login, null: false, unique: true
      String :hashed_password
      String :first_name
      String :last_name
      TrueClass :is_admin, default: false
      DateTime :lastlogin_at
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down { drop_table(:users) }
end
