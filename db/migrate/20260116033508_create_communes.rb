class CreateCommunes < ActiveRecord::Migration[8.1]
  def change
    create_table :communes do |t|
      t.string :name
      t.references :region, null: false, foreign_key: true

      t.timestamps
    end
  end
end
