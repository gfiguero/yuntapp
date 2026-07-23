require "test_helper"

class ListingPricingTest < ActiveSupport::TestCase
  setup do
    @association = neighborhood_associations(:manios_de_buin)
    @admin = users(:selendis)
  end

  test "valid with required fields" do
    listing_pricings(:manios_listing_pricing).destroy
    pricing = ListingPricing.new(
      neighborhood_association: @association,
      price: 1500,
      effective_from: Time.current,
      created_by: @admin
    )
    assert pricing.valid?
  end

  test "rejects price below 1000 (BR-084)" do
    pricing = ListingPricing.new(
      neighborhood_association: @association,
      price: 999,
      effective_from: Time.current,
      created_by: @admin
    )
    assert_not pricing.valid?
    assert pricing.errors[:price].any?
  end

  test "current_for returns active pricing" do
    assert_equal listing_pricings(:manios_listing_pricing), ListingPricing.current_for(@association)
  end

  test "current_for returns nil when no pricing defined" do
    listing_pricings(:manios_listing_pricing).destroy
    assert_nil ListingPricing.current_for(@association)
  end

  test "creating new pricing closes previous one (BR-084)" do
    previous = listing_pricings(:manios_listing_pricing)
    assert_nil previous.effective_to

    new_pricing = ListingPricing.create!(
      neighborhood_association: @association,
      price: 2000,
      effective_from: Time.current,
      created_by: @admin
    )

    previous.reload
    assert_not_nil previous.effective_to
    assert_nil new_pricing.effective_to
    assert_equal new_pricing, ListingPricing.current_for(@association)
  end
end
