class CreateResidenceCertificates < ActiveRecord::Migration[8.1]
  def change
    create_table :residence_certificates do |t|
      t.references :neighborhood_association, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.references :household_unit, null: false, foreign_key: true
      t.references :approved_by, null: true, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.string :folio
      t.text :purpose
      t.text :notes
      t.date :issue_date
      t.date :expiration_date
      t.timestamps
    end

    add_index :residence_certificates, [:neighborhood_association_id, :folio], unique: true, name: "index_residence_certificates_on_association_and_folio"
  end
end
