class AddCommuneToHouseholdUnits < ActiveRecord::Migration[8.1]
  def change
    add_reference :household_units, :commune, null: true, foreign_key: true
  end
end
