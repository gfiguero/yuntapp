class CreateCertificatePricings < ActiveRecord::Migration[8.1]
  def change
    create_table :certificate_pricings do |t|
      t.references :neighborhood_association, null: false, foreign_key: true
      t.integer :price, null: false
      t.datetime :effective_from, null: false
      t.datetime :effective_to
      t.references :created_by, null: false, foreign_key: {to_table: :users}

      t.timestamps
    end

    add_index :certificate_pricings, [:neighborhood_association_id, :effective_from],
      name: "idx_certificate_pricings_on_assoc_and_from"
  end
end
