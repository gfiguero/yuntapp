class RemovePersonalDataFromUsersAndMembers < ActiveRecord::Migration[8.1]
  def change
    # Remove personal data from users
    remove_column :users, :first_name, :string
    remove_column :users, :last_name, :string
    remove_reference :users, :household_unit, foreign_key: true

    # Remove personal data from members
    remove_column :members, :first_name, :string
    remove_column :members, :last_name, :string
    remove_column :members, :run, :string
    remove_column :members, :phone, :string
    remove_column :members, :email, :string
    remove_reference :members, :user, foreign_key: true

    # Make persona_id NOT NULL on members
    change_column_null :members, :persona_id, false
  end
end
