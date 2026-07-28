class AddActiveToNeighborhoodAssociations < ActiveRecord::Migration[8.1]
  def change
    # BR-054: una junta se disuelve marcándola inactive, nunca destruyéndola.
    # Las juntas existentes quedan activas por defecto.
    add_column :neighborhood_associations, :active, :boolean, default: true, null: false
  end
end
