class CreateIdentityVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :identity_verification_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :neighborhood_association, null: false, foreign_key: true
      t.string :run
      t.string :first_name
      t.string :last_name
      t.string :phone
      t.string :status, default: "pending", null: false
      t.text :rejection_reason

      t.timestamps
    end
  end
end
