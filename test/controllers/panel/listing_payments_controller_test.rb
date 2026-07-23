require "test_helper"

module Panel
  class ListingPaymentsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @member_user = users(:selendis)
      @non_member = users(:karass)
      @listing = Listing.create!(name: "Pagable", user: @member_user)
    end

    test "redirects when user is not signed in" do
      get new_panel_listing_payment_url(listing_id: @listing.id)
      assert_redirected_to new_user_session_url
    end

    test "redirects when listing belongs to another user" do
      sign_in @non_member
      get new_panel_listing_payment_url(listing_id: @listing.id)
      assert_response :not_found
    rescue ActiveRecord::RecordNotFound
      # find en el scope del usuario levanta RecordNotFound: aceptable
      assert true
    end

    test "redirects when user has no active member (BR-084)" do
      listing = Listing.create!(name: "Sin junta", user: @non_member)
      sign_in @non_member
      get new_panel_listing_payment_url(listing_id: listing.id)
      assert_redirected_to panel_listing_url(listing)
      assert_equal I18n.t("panel.listing_payments.flash.not_member"), flash[:alert]
    end

    test "redirects when association has no listing price (BR-084)" do
      listing_pricings(:manios_listing_pricing).destroy
      sign_in @member_user
      get new_panel_listing_payment_url(listing_id: @listing.id)
      assert_redirected_to panel_listing_url(@listing)
      assert_equal I18n.t("panel.listing_payments.flash.no_price"), flash[:alert]
    end

    test "redirects when listing is already published and current" do
      @listing.mark_as_paid!(payment_id: "MP-PUB")
      sign_in @member_user
      get new_panel_listing_payment_url(listing_id: @listing.id)
      assert_redirected_to panel_listing_url(@listing)
      assert_equal I18n.t("panel.listing_payments.flash.not_payable"), flash[:alert]
    end

    test "snapshots amount and redirects to MP checkout (BR-083/BR-084)" do
      fake = Object.new
      fake.define_singleton_method(:create_listing_preference) do |_listing, **_kw|
        {"init_point" => "https://mp.test/checkout/123"}
      end

      sign_in @member_user
      stub_class_method(MercadopagoService, :new, fake) do
        get new_panel_listing_payment_url(listing_id: @listing.id)
      end

      assert_redirected_to "https://mp.test/checkout/123"
      @listing.reload
      assert_equal 1200, @listing.amount
      assert_equal 120, @listing.platform_fee
      assert_equal neighborhood_associations(:manios_de_buin), @listing.neighborhood_association
    end
  end
end
