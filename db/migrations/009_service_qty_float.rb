Sequel.migration do
  up do
    set_column_type :services, :qty, Float
  end

  down do
    set_column_type :services, :qty, Integer
  end
end
