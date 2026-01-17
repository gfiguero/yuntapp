class CreateNeighborhoodUnits < ActiveRecord::Migration[8.1]
  def change
    create_table :neighborhood_units do |t|
      t.string :name
      t.references :neighborhood_association, null: false, foreign_key: true

      t.timestamps
    end
  end
end
