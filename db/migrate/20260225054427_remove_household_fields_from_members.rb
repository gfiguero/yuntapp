class RemoveHouseholdFieldsFromMembers < ActiveRecord::Migration[8.1]
  def change
    change_column_null :members, :neighborhood_association_id, false
    remove_reference :members, :household_unit, foreign_key: true
    remove_column :members, :household_admin, :boolean, default: false
  end
end
