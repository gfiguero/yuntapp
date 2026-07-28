require "test_helper"

class HouseholdUnitTest < ActiveSupport::TestCase
  # BR-100: un domicilio con residencias no puede destruirse.
  test "a household unit with residencies cannot be destroyed" do
    hu = household_units(:selendis_household)
    assert hu.residencies.exists?, "el fixture debe tener residencias"

    assert_not hu.destroy, "destroy debe bloquearse por restrict_with_error"
    assert HouseholdUnit.exists?(hu.id)
  end

  test "current_residencies returns the latest approved residency per identity (#97)" do
    hu = household_units(:selendis_household)
    identity = verified_identities(:selendis_persona)
    residence = verified_residences(:selendis_verified_residence)

    # Estancia previa (más antigua) de la misma identidad en el mismo domicilio.
    older = Residency.create!(
      verified_identity: identity, verified_residence: residence,
      household_unit: hu, household_admin: true, status: "approved",
      created_at: 2.years.ago
    )
    # La fixture selendis_residency (misma identidad) es más reciente.
    current = residencies(:selendis_residency)

    ids = hu.current_residencies.map(&:id)
    assert_includes ids, current.id
    assert_not_includes ids, older.id, "no debe listar la estancia antigua de la misma persona"
    # Una sola fila por identidad.
    assert_equal hu.current_residencies.map(&:verified_identity_id).uniq.length,
      hu.current_residencies.length
  end

  test "current_residencies includes distinct identities once each" do
    hu = household_units(:selendis_household)
    ids = hu.current_residencies.map(&:verified_identity_id)
    assert_equal ids, ids.uniq
    assert_includes ids, verified_identities(:selendis_persona).id
    assert_includes ids, verified_identities(:vorazun_persona).id
  end
end
