Sequel.migration do
  up do
    create_table(:divisions) do
      primary_key :id
      String :name
      DateTime :created_at
      DateTime :updated_at
    end

    create_table(:categories) do
      primary_key :id
      foreign_key :division_id, :divisions
      String :name
      DateTime :created_at
      DateTime :updated_at
    end

    create_table(:billing_codes) do
      primary_key :id
      foreign_key :category_id, :categories
      String :code
      String :desc
      String :notes
      Float :rate
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down do
    drop_table(:billing_codes)
    drop_table(:categories)
    drop_table(:divisions)
  end
end
