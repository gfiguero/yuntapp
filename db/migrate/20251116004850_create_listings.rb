class CreateListings < ActiveRecord::Migration[8.1]
  def change
    create_table :listings do |t|
      t.string :name
      t.text :description
      t.decimal :price
      t.boolean :active
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
