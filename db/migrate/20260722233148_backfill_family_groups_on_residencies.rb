class BackfillFamilyGroupsOnResidencies < ActiveRecord::Migration[8.1]
  # Residencies aprobadas antes de que existiera FamilyGroup (BR-056) quedaron
  # con family_group_id nil y rompen los flujos que asumen el grupo presente
  # (ej. panel/dependents). Se crea un FamilyGroup por HouseholdUnit afectado
  # y se asigna a todas sus residencies huérfanas — semántica pre-FamilyGroup:
  # un núcleo familiar por domicilio.
  class MigrationResidency < ActiveRecord::Base
    self.table_name = "residencies"
  end

  class MigrationFamilyGroup < ActiveRecord::Base
    self.table_name = "family_groups"
  end

  def up
    MigrationResidency.where(family_group_id: nil).distinct.pluck(:household_unit_id).each do |household_unit_id|
      family_group = MigrationFamilyGroup.create!(household_unit_id: household_unit_id)
      MigrationResidency.where(family_group_id: nil, household_unit_id: household_unit_id)
        .update_all(family_group_id: family_group.id)
    end
  end

  def down
    # No-op: no hay forma de distinguir los grupos creados por este backfill
    # de los creados por el flujo normal, y revertirlos rompería datos válidos.
  end
end
