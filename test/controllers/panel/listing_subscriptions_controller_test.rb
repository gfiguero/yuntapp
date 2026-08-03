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

    test "new renders the email confirmation form prefilled with login email" do
      sign_in @member_user
      get new_panel_listing_subscription_url(listing_id: @listing.id)
      assert_response :success
      assert_select "input[name=mercadopago_email][value=?]", @member_user.email
    end

    test "new prefills the saved mercadopago_email when present" do
      @member_user.update!(mercadopago_email: "pagador@mp.cl")
      sign_in @member_user
      get new_panel_listing_subscription_url(listing_id: @listing.id)
      assert_response :success
      assert_select "input[name=mercadopago_email][value=?]", "pagador@mp.cl"
    end

    test "create saves the email, snapshots amount, creates preapproval and redirects to MP (BR-088/BR-142)" do
      fake = Object.new
      fake.define_singleton_method(:create_listing_subscription) do |_listing, **_kw|
        {"id" => "PRE-CTRL-1", "init_point" => "https://mp.test/subscription/123"}
      end
      sign_in @member_user
      stub_class_method(MercadopagoService, :new, fake) do
        post panel_listing_subscriptions_url(listing_id: @listing.id),
          params: {mercadopago_email: "pagador@mp.cl"}
      end
      assert_redirected_to "https://mp.test/subscription/123"
      assert_equal "pagador@mp.cl", @member_user.reload.mercadopago_email
      @listing.reload
      assert_equal 1200, @listing.amount
      assert_equal "PRE-CTRL-1", @listing.preapproval_id
      assert_equal "pending", @listing.subscription_status
    end

    test "create uses the confirmed email as payer_email" do
      captured = {}
      fake = Object.new
      fake.define_singleton_method(:create_listing_subscription) do |_listing, **kw|
        captured[:payer_email] = kw[:payer_email]
        {"id" => "PRE-X", "init_point" => "https://mp.test/x"}
      end
      sign_in @member_user
      stub_class_method(MercadopagoService, :new, fake) do
        post panel_listing_subscriptions_url(listing_id: @listing.id),
          params: {mercadopago_email: "elegido@mp.cl"}
      end
      assert_equal "elegido@mp.cl", captured[:payer_email]
    end

    test "create with an invalid email redirects back to the form with an alert" do
      sign_in @member_user
      post panel_listing_subscriptions_url(listing_id: @listing.id),
        params: {mercadopago_email: "no-es-email"}
      assert_redirected_to new_panel_listing_subscription_url(listing_id: @listing.id)
      assert_equal I18n.t("panel.listing_subscriptions.flash.invalid_email"), flash[:alert]
      assert_nil @member_user.reload.mercadopago_email
    end

    test "create shows an actionable alert when MP does not return init_point" do
      fake = Object.new
      fake.define_singleton_method(:create_listing_subscription) { |_l, **_kw| {"message" => "Internal server error"} }
      sign_in @member_user
      stub_class_method(MercadopagoService, :new, fake) do
        post panel_listing_subscriptions_url(listing_id: @listing.id),
          params: {mercadopago_email: "pagador@mp.cl"}
      end
      assert_redirected_to panel_listing_url(@listing)
      assert_equal I18n.t("panel.listing_subscriptions.flash.subscription_failed", email: "pagador@mp.cl"), flash[:alert]
      assert_nil @listing.reload.preapproval_id
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

    # BR-088: si MP ya dejó la preapproval en un estado terminal (el usuario la
    # canceló desde la app de MP, o MP la dio de baja tras cobros fallidos), el
    # update a MP falla. Antes ese error no se rescataba: 500 al usuario y la
    # suscripción local intacta, sin forma de salir del estado.
    test "cancel se completa aunque MP rechace la cancelación (BR-088)" do
      @listing.update!(preapproval_id: "PRE-CTRL-3", subscription_status: "authorized")
      fake = Object.new
      fake.define_singleton_method(:cancel_preapproval) { |id| raise StandardError, "preapproval already cancelled" }

      sign_in @member_user
      stub_class_method(MercadopagoService, :new, fake) do
        delete cancel_panel_listing_subscriptions_url(listing_id: @listing.id)
      end

      assert_redirected_to panel_listing_url(@listing)
      assert_equal I18n.t("panel.listing_subscriptions.flash.cancelled"), flash[:notice]
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
