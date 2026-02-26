class CreateVerifiedResidences < ActiveRecord::Migration[8.1]
  def change
    create_table :verified_residences do |t|
      t.string :verification_status, null: false, default: "pending"
      t.string :address_line_1
      t.string :address_line_2
      t.string :number
      t.boolean :manual_address, default: false
      t.references :neighborhood_delegation, null: true, foreign_key: true
      t.references :commune, null: true, foreign_key: true
      t.references :neighborhood_association, null: false, foreign_key: true
      t.references :residence_verification_request, null: true, foreign_key: true

      t.timestamps
    end

    # Replace residence_verification_request reference on household_units with verified_residence
    remove_reference :household_units, :residence_verification_request, foreign_key: true
    add_reference :household_units, :verified_residence, null: true, foreign_key: true
  end
end
