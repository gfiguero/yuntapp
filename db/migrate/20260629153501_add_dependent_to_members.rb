class AddDependentToMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :members, :dependent, :boolean, default: false, null: false
    add_index :members, :dependent
  end
end
