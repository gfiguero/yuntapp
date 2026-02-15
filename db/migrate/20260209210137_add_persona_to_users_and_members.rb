class AddPersonaToUsersAndMembers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :persona, null: true, foreign_key: true
    add_reference :members, :persona, null: true, foreign_key: true
  end
end
