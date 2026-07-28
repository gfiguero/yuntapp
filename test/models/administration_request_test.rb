require "test_helper"

class AdministrationRequestTest < ActiveSupport::TestCase
  def base_attrs(overrides = {})
    {
      user: users(:urunis),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      organization_rut: "83014859-0",
      position: "presidente",
      first_name: "juan",
      last_name: "pérez",
      run: "16.912.345-4",
      phone: "987654321",
      status: "pending"
    }.merge(overrides)
  end

  test "normaliza run, rut, telefono y nombres" do
    r = AdministrationRequest.new(base_attrs)
    r.valid?
    assert_equal "16912345-4", r.run
    assert_equal "83014859-0", r.organization_rut
    assert_equal "+56987654321", r.phone
    assert_equal "Juan", r.first_name
    assert_equal "Pérez", r.last_name
  end

  test "pending exige cargo valido" do
    r = AdministrationRequest.new(base_attrs(position: "capataz"))
    assert_not r.valid?
    assert_includes r.errors.attribute_names, :position
  end

  test "pending exige rut de organizacion valido" do
    r = AdministrationRequest.new(base_attrs(organization_rut: "83014859-5"))
    assert_not r.valid?
    assert_includes r.errors.attribute_names, :organization_rut
  end

  test "pending exige junta existente o nombre+comuna nuevos" do
    r = AdministrationRequest.new(base_attrs(neighborhood_association: nil, proposed_association_name: nil))
    assert_not r.valid?
    assert_includes r.errors.attribute_names, :base
  end

  test "acepta junta nueva con nombre y comuna" do
    r = AdministrationRequest.new(base_attrs(
      neighborhood_association: nil,
      proposed_association_name: "Junta Nueva Los Robles",
      commune: communes(:commune_0_0_0)
    ))
    assert r.valid?, r.errors.full_messages.to_sentence
  end

  test "un usuario no puede tener dos solicitudes activas" do
    AdministrationRequest.create!(base_attrs)
    dup = AdministrationRequest.new(base_attrs)
    assert_not dup.valid?
    assert_includes dup.errors.attribute_names, :base
  end

  test "submit! pasa de draft a pending" do
    r = AdministrationRequest.create!(base_attrs(status: "draft"))
    r.submit!
    assert r.pending?
  end

  test "cancel! solo desde pending" do
    r = AdministrationRequest.create!(base_attrs)
    r.cancel!
    assert r.cancelled?
  end
end
