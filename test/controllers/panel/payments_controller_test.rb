require "test_helper"

module Panel
  class PaymentsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @household_admin = users(:selendis)
      @non_admin = users(:karass)
      @certificate = ResidenceCertificate.create!(
        member: members(:selendis_member),
        household_unit: household_units(:selendis_household),
        neighborhood_association: neighborhood_associations(:manios_de_buin),
        purpose: "trámite bancario",
        amount: 1500,
        status: "pending_payment"
      )
    end

    def stub_mercadopago(preference: nil, &block)
      response = preference || {"init_point" => "https://mp.test/checkout/abc", "id" => "PREF-XYZ"}
      fake = Object.new
      fake.define_singleton_method(:create_preference) do |*args, **kw|
        response
      end
      stub_class_method(MercadopagoService, :new, fake, &block)
    end

    # --- Authorization ---

    test "non household_admin is redirected from new" do
      sign_in @non_admin
      get new_panel_payment_url(certificate_id: @certificate.id)
      assert_redirected_to panel_root_url
    end

    test "unauthenticated is redirected from new" do
      get new_panel_payment_url(certificate_id: @certificate.id)
      assert_redirected_to new_user_session_url
    end

    # --- new — create preference and redirect ---

    test "new redirects to MP init_point with valid preference" do
      sign_in @household_admin

      stub_mercadopago do
        get new_panel_payment_url(certificate_id: @certificate.id)
      end

      assert_redirected_to "https://mp.test/checkout/abc"
    end

    test "new returns 404 for certificate not belonging to user" do
      other_cert = ResidenceCertificate.create!(
        member: members(:selendis_member),
        household_unit: household_units(:matching_karax_household),
        neighborhood_association: neighborhood_associations(:manios_de_buin),
        purpose: "ajeno",
        amount: 1500
      )

      sign_in @household_admin
      stub_mercadopago do
        get new_panel_payment_url(certificate_id: other_cert.id)
      end
      assert_response :not_found
    end

    test "new redirects when certificate is already paid (BR-002 / ensure_pending)" do
      @certificate.update!(status: "paid", payment_id: "MP-PRE-PAID", paid_at: Time.current)

      sign_in @household_admin
      stub_mercadopago do
        get new_panel_payment_url(certificate_id: @certificate.id)
      end

      assert_redirected_to panel_residence_certificate_path(@certificate)
    end

    test "new redirects with alert when preference returns no init_point" do
      sign_in @household_admin

      stub_mercadopago(preference: {"id" => "PREF-ONLY"}) do
        get new_panel_payment_url(certificate_id: @certificate.id)
      end

      assert_redirected_to panel_residence_certificate_path(@certificate)
    end

    test "new redirects with alert when MercadoPago is not configured" do
      sign_in @household_admin

      fake = Object.new
      fake.define_singleton_method(:create_preference) do |*args, **kw|
        raise MercadopagoService::ConfigurationError, "no token"
      end

      stub_class_method(MercadopagoService, :new, fake) do
        get new_panel_payment_url(certificate_id: @certificate.id)
      end

      assert_redirected_to panel_residence_certificate_path(@certificate)
      assert_equal I18n.t("panel.payments.flash.misconfigured"), flash[:alert]
    end

    # --- success/failure/pending render ---

    test "success renders" do
      sign_in @household_admin
      get success_panel_payments_url(external_reference: @certificate.id)
      assert_response :success
    end

    test "failure renders" do
      sign_in @household_admin
      get failure_panel_payments_url(external_reference: @certificate.id)
      assert_response :success
    end

    test "pending renders" do
      sign_in @household_admin
      get pending_panel_payments_url(external_reference: @certificate.id)
      assert_response :success
    end

    test "success renders even without external_reference" do
      sign_in @household_admin
      get success_panel_payments_url
      assert_response :success
    end
  end
end
