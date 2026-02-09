class AddSuperadminAndAssociationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :superadmin, :boolean, default: false
    add_reference :users, :neighborhood_association, null: true, foreign_key: true
  end
end
