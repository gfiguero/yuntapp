class AddNeighborhoodAssociationToMembers < ActiveRecord::Migration[8.1]
  def change
    add_reference :members, :neighborhood_association, foreign_key: true
  end
end
