class CreateFamilyGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :family_groups do |t|
      t.references :household_unit, null: false, foreign_key: true
    end
  end
end
