class CreateNeighborhoodAssociations < ActiveRecord::Migration[8.1]
  def change
    create_table :neighborhood_associations do |t|
      t.string :name

      t.timestamps
    end
  end
end
