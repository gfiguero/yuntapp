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

  # BR-119: normalización y validación del rut.
  test "normaliza el rut quitando puntos y agregando guion" do
    na = NeighborhoodAssociation.new(name: "J", rut: "70.207.956-k")
    na.valid?
    assert_equal "70207956-K", na.rut
  end

  test "es invalido sin rut" do
    na = NeighborhoodAssociation.new(name: "J", rut: nil)
    assert_not na.valid?
    assert_includes na.errors.attribute_names, :rut
  end

  test "es invalido con digito verificador incorrecto" do
    na = NeighborhoodAssociation.new(name: "J", rut: "70207956-5")
    assert_not na.valid?
    assert_includes na.errors.attribute_names, :rut
  end

  test "es valido con rut correcto" do
    na = NeighborhoodAssociation.new(name: "J", rut: "71724860-0", commune: communes(:commune_0_0_0))
    assert na.valid?, na.errors.full_messages.to_sentence
  end

  test "rut es unico" do
    existente = neighborhood_associations(:manios_de_buin)
    dup = NeighborhoodAssociation.new(name: "Otra", rut: existente.rut)
    assert_not dup.valid?
    assert_includes dup.errors.attribute_names, :rut
  end
end
