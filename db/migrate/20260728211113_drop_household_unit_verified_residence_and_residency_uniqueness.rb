class DropHouseholdUnitVerifiedResidenceAndResidencyUniqueness < ActiveRecord::Migration[8.1]
  def change
    # #94: Residency es la única dueña de la VerifiedResidence. La columna en
    # HouseholdUnit era redundante y provocaba herencia cruzada entre FamilyGroups.
    remove_reference :household_units, :verified_residence, foreign_key: true

    # #97: permitir historial de estancias — una identidad puede tener varias
    # Residency en el mismo HouseholdUnit a lo largo del tiempo (irse y volver).
    remove_index :residencies,
      column: [:verified_identity_id, :household_unit_id],
      name: "index_residencies_on_identity_and_unit",
      unique: true
  end
end
