class CreateListingPricings < ActiveRecord::Migration[8.1]
  def change
    create_table :listing_pricings do |t|
      t.integer :neighborhood_association_id, null: false
      t.integer :price, null: false
      t.datetime :effective_from, null: false
      t.datetime :effective_to
      t.integer :created_by_id, null: false

      t.timestamps
    end

    add_index :listing_pricings, :neighborhood_association_id
    add_index :listing_pricings, [:neighborhood_association_id, :effective_to],
      name: "index_listing_pricings_on_association_and_effective_to"
    add_foreign_key :listing_pricings, :neighborhood_associations
    add_foreign_key :listing_pricings, :users, column: :created_by_id
  end
end
