require "test_helper"

class PaymentEventTest < ActiveSupport::TestCase
  def setup
    @listing = Listing.create!(name: "Pub", user: users(:artanis), amount: 1200)
  end

  test "valid with payment_id, status, payable and processed_at" do
    event = PaymentEvent.new(
      payment_id: "MP-1", status: "approved", payable: @listing,
      amount: 1200, processed_at: Time.current
    )
    assert event.valid?, event.errors.full_messages.to_sentence
  end

  test "requires payment_id, status and processed_at" do
    event = PaymentEvent.new(payable: @listing)
    assert_not event.valid?
    assert event.errors[:payment_id].any?
    assert event.errors[:status].any?
    assert event.errors[:processed_at].any?
  end

  test "same payment_id with different status is allowed (approved then refunded)" do
    PaymentEvent.create!(payment_id: "MP-2", status: "approved", payable: @listing, processed_at: Time.current)
    reverted = PaymentEvent.new(payment_id: "MP-2", status: "refunded", payable: @listing, processed_at: Time.current)
    assert reverted.valid?, "un mismo payment_id con otro status debe permitirse (#101)"
    assert reverted.save
  end

  test "duplicate (payment_id, status) is rejected" do
    PaymentEvent.create!(payment_id: "MP-3", status: "approved", payable: @listing, processed_at: Time.current)
    dup = PaymentEvent.new(payment_id: "MP-3", status: "approved", payable: @listing, processed_at: Time.current)
    assert_not dup.valid?
    assert dup.errors[:payment_id].any?
  end

  test "payable can be a ResidenceCertificate (polymorphic)" do
    cert = ResidenceCertificate.create!(
      member: members(:selendis_member), household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin), purpose: "t",
      status: "pending_payment", amount: 1500
    )
    event = PaymentEvent.create!(payment_id: "MP-C1", status: "approved", payable: cert, processed_at: Time.current)
    assert_equal cert, event.payable
    assert_includes cert.payment_events, event
  end
end
