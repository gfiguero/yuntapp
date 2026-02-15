class RenamePersonasToVerifiedIdentities < ActiveRecord::Migration[8.1]
  def change
    rename_table :personas, :verified_identities
    rename_column :users, :persona_id, :verified_identity_id
    rename_column :members, :persona_id, :verified_identity_id
  end
end
