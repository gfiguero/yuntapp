require "test_helper"

class RegionTest < ActiveSupport::TestCase
  # BR-100: ver CountryTest — no se borra geografía con dependientes.
  test "cannot be destroyed while it has communes (BR-100)" do
    region = regions(:region_0_0)
    assert region.communes.exists?

    assert_no_difference -> { Commune.count } do
      assert_not region.destroy
    end

    assert Region.exists?(region.id)
    assert_not_empty region.errors[:base]
  end

  test "can be destroyed when it has no communes" do
    region = Region.create!(name: "Región de prueba", country: countries(:country_0))

    assert region.destroy
    assert_not Region.exists?(region.id)
  end
end
