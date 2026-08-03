require "test_helper"

class CommuneTest < ActiveSupport::TestCase
  # BR-100: sin `dependent`, borrar la comuna dejaba las juntas y los domicilios
  # apuntando a una comuna inexistente (nullify por defecto).
  test "cannot be destroyed while it has neighborhood associations (BR-100)" do
    commune = neighborhood_associations(:association_0).commune

    assert_no_difference -> { NeighborhoodAssociation.count } do
      assert_not commune.destroy
    end

    assert Commune.exists?(commune.id)
    assert_not_empty commune.errors[:base]
  end

  test "can be destroyed when nothing depends on it" do
    commune = Commune.create!(name: "Comuna de prueba", region: regions(:region_0_0))

    assert commune.destroy
    assert_not Commune.exists?(commune.id)
  end
end
