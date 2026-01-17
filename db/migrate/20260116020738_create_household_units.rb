class CreateHouseholdUnits < ActiveRecord::Migration[8.1]
  def change
    create_table :household_units do |t|
      t.string :number
      t.references :neighborhood_unit, null: false, foreign_key: true

      t.timestamps
    end
  end
end
