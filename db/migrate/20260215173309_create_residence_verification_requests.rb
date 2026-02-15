class CreateResidenceVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :residence_verification_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :neighborhood_association, null: false, foreign_key: true
      t.references :neighborhood_delegation, null: false, foreign_key: true
      t.string :address_line_1
      t.string :address_line_2
      t.string :number
      t.string :city
      t.string :region
      t.string :country
      t.string :postal_code
      t.references :commune, null: false, foreign_key: true
      t.string :status, default: "pending", null: false
      t.text :rejection_reason

      t.timestamps
    end
  end
end
