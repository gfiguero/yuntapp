require "test_helper"

class HouseholdUnitTest < ActiveSupport::TestCase
  # BR-100: un domicilio con residencias no puede destruirse.
  test "a household unit with residencies cannot be destroyed" do
    hu = household_units(:selendis_household)
    assert hu.residencies.exists?, "el fixture debe tener residencias"

    assert_not hu.destroy, "destroy debe bloquearse por restrict_with_error"
    assert HouseholdUnit.exists?(hu.id)
  end
end
