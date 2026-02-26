class RemoveVerificationStatusFromVerifiedIdentitiesAndVerifiedResidences < ActiveRecord::Migration[8.1]
  def change
    remove_index :verified_identities, :verification_status
    remove_column :verified_identities, :verification_status, :string, default: "pending", null: false
    remove_column :verified_residences, :verification_status, :string, default: "pending", null: false
  end
end
