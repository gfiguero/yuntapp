class AddCommuneToNeighborhoodAssociations < ActiveRecord::Migration[8.1]
  def change
    add_reference :neighborhood_associations, :commune, null: true, foreign_key: true
  end
end
