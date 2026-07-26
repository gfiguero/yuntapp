require "test_helper"

class NeighborhoodAssociationTest < ActiveSupport::TestCase
  setup do
    @association = neighborhood_associations(:manios_de_buin)
  end

  # BR-054: disolver marca la junta inactive.
  test "deactivate! marks the association inactive" do
    @association.deactivate!
    assert_not @association.reload.active?
    assert @association.inactive?
  end

  # BR-054: los socios activos pasan a inactive en cascada.
  test "deactivate! cascades active members to inactive" do
    member = members(:selendis_member)
    assert member.approved?

    @association.deactivate!

    assert member.reload.inactive?
  end

  # BR-055/BR-100: la disolución conserva el historial, no destruye.
  test "deactivate! preserves the association and its members" do
    member_id = members(:selendis_member).id
    @association.deactivate!

    assert NeighborhoodAssociation.exists?(@association.id)
    assert Member.exists?(member_id)
  end

  # BR-100: una junta con delegaciones no puede destruirse.
  test "a neighborhood association with delegations cannot be destroyed" do
    assert @association.neighborhood_delegations.exists?, "el fixture debe tener delegaciones"

    assert_not @association.destroy, "destroy debe bloquearse por restrict_with_error"
    assert NeighborhoodAssociation.exists?(@association.id)
  end
end
