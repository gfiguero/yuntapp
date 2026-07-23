require "test_helper"

# Ciclo de publicación pagada del marketplace (BR-083, BR-085, BR-086, BR-087).
class ListingPublicationTest < ActiveSupport::TestCase
  setup do
    @listing = Listing.create!(name: "Test listing", user: users(:artanis))
  end

  test "new listing starts as pending_payment (BR-083)" do
    assert @listing.pending_payment?
    assert_not @listing.published?
    assert @listing.payable?
  end

  test "mark_as_paid! publishes for 30 days (BR-086)" do
    @listing.mark_as_paid!(payment_id: "MP-1")

    assert @listing.published?
    assert_equal "MP-1", @listing.payment_id
    assert_equal Date.current + 30.days, @listing.published_until
    assert_not @listing.payable?
  end

  test "mark_as_paid! is idempotent for same payment_id (BR-087)" do
    @listing.mark_as_paid!(payment_id: "MP-1")
    original_until = @listing.published_until

    @listing.mark_as_paid!(payment_id: "MP-1")
    assert_equal original_until, @listing.reload.published_until
  end

  test "mark_as_paid! raises for different payment_id while published (BR-087)" do
    @listing.mark_as_paid!(payment_id: "MP-1")

    assert_raises(Listing::AlreadyPaidError) do
      @listing.mark_as_paid!(payment_id: "MP-2")
    end
  end

  test "expired publication can be renewed with a new payment (BR-086)" do
    @listing.mark_as_paid!(payment_id: "MP-1")
    @listing.update_columns(published_until: 2.days.ago.to_date)

    assert @listing.publication_expired?
    assert @listing.payable?

    @listing.mark_as_paid!(payment_id: "MP-2")
    assert @listing.published?
    assert_equal Date.current + 30.days, @listing.published_until
  end

  test "platform fee is 10 percent of amount (BR-085)" do
    @listing.update!(amount: 1500)
    assert_equal 150, @listing.platform_fee
  end

  test "published scope excludes pending and expired" do
    published = Listing.create!(name: "published", user: users(:artanis))
    published.mark_as_paid!(payment_id: "MP-scope-1")

    expired = Listing.create!(name: "expired", user: users(:artanis))
    expired.mark_as_paid!(payment_id: "MP-scope-2")
    expired.update_columns(published_until: 1.day.ago.to_date)

    assert_includes Listing.published, published
    assert_not_includes Listing.published, expired
    assert_not_includes Listing.published, @listing
  end
end
