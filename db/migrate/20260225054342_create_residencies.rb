class CreateResidencies < ActiveRecord::Migration[8.1]
  def change
    create_table :residencies do |t|
      t.references :verified_identity, null: false, foreign_key: true
      t.references :verified_residence, null: false, foreign_key: true
      t.references :household_unit, null: false, foreign_key: true
      t.boolean :household_admin, default: false
      t.string :status, null: false, default: "approved"
      t.timestamps
    end

    add_index :residencies, [:verified_identity_id, :household_unit_id],
      unique: true, name: "index_residencies_on_identity_and_unit"
  end
end
