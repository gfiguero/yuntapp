require "test_helper"

class CountryTest < ActiveSupport::TestCase
  # BR-100: la geografía es dato de referencia del que cuelgan juntas, domicilios
  # y todo el historial. Con `dependent: :destroy` borrar un país cascadeaba
  # región→comuna y arrastraba/orfanaba las juntas de esas comunas.
  test "cannot be destroyed while it has regions (BR-100)" do
    country = countries(:country_0)
    assert country.regions.exists?

    assert_no_difference -> { Region.count } do
      assert_not country.destroy
    end

    assert Country.exists?(country.id)
    assert_not_empty country.errors[:base]
  end

  test "can be destroyed when it has no regions" do
    country = Country.create!(name: "Uruguay", iso_code: "URY")

    assert country.destroy
    assert_not Country.exists?(country.id)
  end
end
