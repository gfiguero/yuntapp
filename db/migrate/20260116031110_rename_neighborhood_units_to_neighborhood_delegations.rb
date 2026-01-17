class RenameNeighborhoodUnitsToNeighborhoodDelegations < ActiveRecord::Migration[8.1]
  def change
    rename_table :neighborhood_units, :neighborhood_delegations
    rename_column :household_units, :neighborhood_unit_id, :neighborhood_delegation_id
  end
end
