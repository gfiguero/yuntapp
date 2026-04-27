class AddFamilyGroupToResidencies < ActiveRecord::Migration[8.1]
  def change
    add_reference :residencies, :family_group, null: true, foreign_key: true
  end
end
