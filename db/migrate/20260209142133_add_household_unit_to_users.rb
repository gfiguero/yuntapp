class AddHouseholdUnitToUsers < ActiveRecord::Migration[8.1]
  def up
    add_reference :users, :household_unit, foreign_key: true, null: true

    # Migrate existing data: set household_unit_id from member association
    execute <<~SQL
      UPDATE users
      SET household_unit_id = (
        SELECT members.household_unit_id
        FROM members
        WHERE members.user_id = users.id
        LIMIT 1
      )
      WHERE id IN (SELECT user_id FROM members WHERE user_id IS NOT NULL)
    SQL
  end

  def down
    remove_reference :users, :household_unit
  end
end
