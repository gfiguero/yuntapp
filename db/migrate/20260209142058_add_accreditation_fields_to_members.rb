class AddAccreditationFieldsToMembers < ActiveRecord::Migration[8.1]
  def up
    add_column :members, :status, :string, null: false, default: "pending"
    add_column :members, :household_admin, :boolean, default: false
    add_reference :members, :requested_by, foreign_key: {to_table: :users}, null: true
    add_reference :members, :approved_by, foreign_key: {to_table: :users}, null: true
    add_column :members, :approved_at, :datetime
    add_column :members, :rejection_reason, :text
    add_index :members, :status

    # Migrate existing data: mark existing members as approved
    execute "UPDATE members SET status = 'approved'"

    # Mark first member with user_id as household_admin per household_unit
    execute <<~SQL
      UPDATE members
      SET household_admin = 1
      WHERE user_id IS NOT NULL
        AND id IN (
          SELECT MIN(id)
          FROM members
          WHERE user_id IS NOT NULL
          GROUP BY household_unit_id
        )
    SQL
  end

  def down
    remove_index :members, :status
    remove_column :members, :rejection_reason
    remove_column :members, :approved_at
    remove_reference :members, :approved_by
    remove_reference :members, :requested_by
    remove_column :members, :household_admin
    remove_column :members, :status
  end
end
