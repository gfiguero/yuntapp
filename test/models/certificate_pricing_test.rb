require "test_helper"

class CertificatePricingTest < ActiveSupport::TestCase
  setup do
    @association = neighborhood_associations(:manios_de_buin)
    @admin = users(:selendis)
  end

  test "valid with required fields" do
    pricing = CertificatePricing.new(
      neighborhood_association: @association,
      price: 1500,
      effective_from: Time.current,
      created_by: @admin
    )
    # close existing
    certificate_pricings(:manios_current_pricing).destroy
    assert pricing.valid?
  end

  test "requires price" do
    pricing = CertificatePricing.new(neighborhood_association: @association, created_by: @admin, effective_from: Time.current)
    assert_not pricing.valid?
    assert pricing.errors[:price].any?
  end

  test "rejects price below 1000 (BR-005)" do
    pricing = CertificatePricing.new(
      neighborhood_association: @association,
      price: 999,
      effective_from: Time.current,
      created_by: @admin
    )
    assert_not pricing.valid?
    assert pricing.errors[:price].any?
  end

  test "accepts price at 1000" do
    certificate_pricings(:manios_current_pricing).destroy
    pricing = CertificatePricing.new(
      neighborhood_association: @association,
      price: 1000,
      effective_from: Time.current,
      created_by: @admin
    )
    assert pricing.valid?
  end

  test "requires neighborhood_association" do
    pricing = CertificatePricing.new(price: 1500, created_by: @admin, effective_from: Time.current)
    assert_not pricing.valid?
    assert pricing.errors[:neighborhood_association].any?
  end

  test "requires created_by" do
    pricing = CertificatePricing.new(neighborhood_association: @association, price: 1500, effective_from: Time.current)
    assert_not pricing.valid?
    assert pricing.errors[:created_by].any?
  end

  # --- current_for + close_previous_pricing ---

  test "current_for returns active pricing" do
    pricing = certificate_pricings(:manios_current_pricing)
    assert_equal pricing, CertificatePricing.current_for(@association)
  end

  test "current_for returns nil when no pricing defined" do
    certificate_pricings(:manios_current_pricing).destroy
    assert_nil CertificatePricing.current_for(@association)
  end

  test "current_for ignores pricings with effective_to set" do
    certificate_pricings(:manios_current_pricing).update_columns(effective_to: 1.hour.ago)
    assert_nil CertificatePricing.current_for(@association)
  end

  test "creating new pricing closes previous one (BR-070)" do
    previous = certificate_pricings(:manios_current_pricing)
    assert_nil previous.effective_to

    new_pricing = CertificatePricing.create!(
      neighborhood_association: @association,
      price: 2000,
      effective_from: Time.current,
      created_by: @admin
    )

    previous.reload
    assert_not_nil previous.effective_to
    assert previous.effective_to <= Time.current
    assert_nil new_pricing.effective_to
  end

  test "current_for after closing returns new pricing" do
    CertificatePricing.create!(
      neighborhood_association: @association,
      price: 2000,
      effective_from: Time.current,
      created_by: @admin
    )

    current = CertificatePricing.current_for(@association)
    assert_equal 2000, current.price
  end

  test "current_for is scoped per association" do
    other_association = neighborhood_associations(:association_1)
    CertificatePricing.create!(
      neighborhood_association: other_association,
      price: 5000,
      effective_from: Time.current,
      created_by: @admin
    )

    manios_current = CertificatePricing.current_for(@association)
    other_current = CertificatePricing.current_for(other_association)

    assert_equal 1500, manios_current.price
    assert_equal 5000, other_current.price
  end
end
