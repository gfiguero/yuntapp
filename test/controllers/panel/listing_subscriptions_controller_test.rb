require "test_helper"

module Panel
  class ListingSubscriptionsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @member_user = users(:selendis)
      @listing = Listing.create!(name: "Suscribible", user: @member_user)
    end

    test "redirects when user is not signed in" do
      get new_panel_listing_subscription_url(listing_id: @listing.id)
      assert_redirected_to new_user_session_url
    end

    test "redirects when listing already has active subscription" do
      @listing.update!(subscription_status: "authorized")
      sign_in @member_user
      get new_panel_listing_subscription_url(listing_id: @listing.id)
      assert_redirected_to panel_listing_url(@listing)
      assert_equal I18n.t("panel.listing_subscriptions.flash.not_subscribable"), flash[:alert]
    end

    test "redirects when association has no listing price (BR-084)" do
      listing_pricings(:manios_listing_pricing).destroy
      sign_in @member_user
      get new_panel_listing_subscription_url(listing_id: @listing.id)
      assert_redirected_to panel_listing_url(@listing)
      assert_equal I18n.t("panel.listing_payments.flash.no_price"), flash[:alert]
    end

    test "creates preapproval, snapshots amount and redirects to MP (BR-088)" do
      fake = Object.new
      fake.define_singleton_method(:create_listing_subscription) do |_listing, **_kw|
        {"id" => "PRE-CTRL-1", "init_point" => "https://mp.test/subscription/123"}
      end

      sign_in @member_user
      stub_class_method(MercadopagoService, :new, fake) do
        get new_panel_listing_subscription_url(listing_id: @listing.id)
      end

      assert_redirected_to "https://mp.test/subscription/123"
      @listing.reload
      assert_equal 1200, @listing.amount
      assert_equal "PRE-CTRL-1", @listing.preapproval_id
      assert_equal "pending", @listing.subscription_status
    end

    test "cancel cancels subscription in MP and locally (BR-089)" do
      @listing.update!(preapproval_id: "PRE-CTRL-2", subscription_status: "authorized")
      cancelled_ids = []
      fake = Object.new
      fake.define_singleton_method(:cancel_preapproval) { |id| cancelled_ids << id }

      sign_in @member_user
      stub_class_method(MercadopagoService, :new, fake) do
        delete cancel_panel_listing_subscriptions_url(listing_id: @listing.id)
      end

      assert_redirected_to panel_listing_url(@listing)
      assert_equal ["PRE-CTRL-2"], cancelled_ids
      assert_equal "cancelled", @listing.reload.subscription_status
    end

    test "cancel without subscription redirects with alert" do
      sign_in @member_user
      delete cancel_panel_listing_subscriptions_url(listing_id: @listing.id)
      assert_redirected_to panel_listing_url(@listing)
      assert_equal I18n.t("panel.listing_subscriptions.flash.no_subscription"), flash[:alert]
    end
  end
end
