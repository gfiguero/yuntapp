class AddDependentFieldsToIdentityVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    change_table :identity_verification_requests do |t|
      t.boolean :dependent, default: false, null: false
      t.references :family_group, foreign_key: true
      t.references :requested_by, foreign_key: { to_table: :users }
      t.references :neighborhood_association, foreign_key: true
    end

    change_column_null :identity_verification_requests, :user_id, true

    add_index :identity_verification_requests, :dependent
  end
end
