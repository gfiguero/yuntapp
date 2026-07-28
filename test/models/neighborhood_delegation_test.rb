require "test_helper"

class NeighborhoodDelegationTest < ActiveSupport::TestCase
  # BR-100: una delegación con domicilios no puede destruirse.
  test "a delegation with household units cannot be destroyed" do
    delegation = neighborhood_delegations(:manios_delegation_0)
    assert delegation.household_units.exists?, "el fixture debe tener domicilios"

    assert_not delegation.destroy, "destroy debe bloquearse por restrict_with_error"
    assert NeighborhoodDelegation.exists?(delegation.id)
  end
end
