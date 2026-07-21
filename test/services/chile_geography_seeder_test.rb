require "test_helper"

class ChileGeographySeederTest < ActiveSupport::TestCase
  test "seeds Chile with 16 regions and 346 communes" do
    ChileGeographySeeder.call

    chile = Country.find_by(iso_code: "CHL")
    assert_not_nil chile
    assert_equal 16, chile.regions.where.not(code: nil).count
    assert_equal 346, Commune.where(region: chile.regions).where.not(code: nil).count
  end

  test "does not duplicate the country" do
    ChileGeographySeeder.call
    ChileGeographySeeder.call

    assert_equal 1, Country.where(iso_code: "CHL").count
  end

  test "is idempotent across runs" do
    ChileGeographySeeder.call
    regions = Region.where.not(code: nil).count
    communes = Commune.where.not(code: nil).count

    ChileGeographySeeder.call

    assert_equal regions, Region.where.not(code: nil).count
    assert_equal communes, Commune.where.not(code: nil).count
  end

  test "assigns official CUT codes" do
    ChileGeographySeeder.call

    santiago = Commune.find_by(code: "13101")
    assert_equal "Santiago", santiago.name
    assert_equal "13", santiago.region.code
    assert_equal "Metropolitana de Santiago", santiago.region.name
  end

  test "assigns Ñuble communes their 16xxx codes (not legacy 08xxx)" do
    ChileGeographySeeder.call

    nuble = Region.find_by(code: "16")
    assert_equal "Ñuble", nuble.name
    assert_equal 21, nuble.communes.count
    assert nuble.communes.all? { |c| c.code.start_with?("16") }, "toda comuna de Ñuble debe tener código 16xxx"
    assert_equal "16101", Commune.find_by(name: "Chillán", region: nuble).code
  end

  test "orders regions north to south by position" do
    ChileGeographySeeder.call

    ordered = Region.where.not(position: nil).order(:position)
    assert_equal "Arica y Parinacota", ordered.first.name
    assert_equal "Magallanes y de la Antártica Chilena", ordered.last.name
    assert_equal (1..16).to_a, ordered.pluck(:position)
  end

  test "raises ChecksumError when data is incomplete" do
    incomplete = Rails.root.join("tmp/incomplete_chile.yml")
    File.write(incomplete, {"country" => {"name" => "Chile", "iso_code" => "CHL"}, "regions" => []}.to_yaml)

    assert_raises(ChileGeographySeeder::ChecksumError) do
      ChileGeographySeeder.call(path: incomplete)
    end
  ensure
    File.delete(incomplete) if incomplete && File.exist?(incomplete)
  end
end
