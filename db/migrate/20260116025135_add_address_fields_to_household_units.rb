class AddAddressFieldsToHouseholdUnits < ActiveRecord::Migration[8.1]
  def change
    add_column :household_units, :address_line_1, :string
    add_column :household_units, :address_line_2, :string
    add_column :household_units, :city, :string
    add_column :household_units, :region, :string
    add_column :household_units, :country, :string
    add_column :household_units, :postal_code, :string
  end
end
