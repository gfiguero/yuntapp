class BackfillResidenciesAndMemberAssociations < ActiveRecord::Migration[8.1]
  def up
    # Backfill neighborhood_association_id on members
    execute <<~SQL
      UPDATE members
      SET neighborhood_association_id = (
        SELECT nd.neighborhood_association_id
        FROM household_units hu
        JOIN neighborhood_delegations nd ON nd.id = hu.neighborhood_delegation_id
        WHERE hu.id = members.household_unit_id
      )
      WHERE neighborhood_association_id IS NULL
    SQL

    # Create Residency records from existing Members that have a household_unit with a verified_residence
    execute <<~SQL
      INSERT INTO residencies (verified_identity_id, verified_residence_id, household_unit_id, household_admin, status, created_at, updated_at)
      SELECT m.verified_identity_id, hu.verified_residence_id, m.household_unit_id, m.household_admin, m.status, m.created_at, m.updated_at
      FROM members m
      JOIN household_units hu ON hu.id = m.household_unit_id
      WHERE hu.verified_residence_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM residencies r
        WHERE r.verified_identity_id = m.verified_identity_id
        AND r.household_unit_id = m.household_unit_id
      )
    SQL
  end

  def down
    execute "DELETE FROM residencies"
    execute "UPDATE members SET neighborhood_association_id = NULL"
  end
end
