require "test_helper"

module Admin
  class ResidenceCertificatesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @admin = users(:selendis)
      @cert = ResidenceCertificate.create!(
        member: members(:selendis_member),
        household_unit: household_units(:selendis_household),
        neighborhood_association: neighborhood_associations(:manios_de_buin),
        purpose: "trámite bancario",
        status: "issued",
        folio: "CR-1-501",
        validation_token: SecureRandom.uuid,
        validation_code: "ADMINTST",
        issue_date: Date.current,
        expiration_date: Date.current + 6.months,
        issued_at: Time.current
      )
    end

    # BR-077: la emisión manual fue eliminada. La emisión es exclusivamente
    # automática vía IssueCertificateJob después de confirmar el pago (BR-062).
    test "issue route helper is no longer defined" do
      assert_not Rails.application.routes.url_helpers.respond_to?(:issue_admin_residence_certificate_path),
        "issue_admin_residence_certificate_path should not exist after BR-077"
    end

    test "issue route is not recognized" do
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/admin/residence_certificates/1/issue", method: :patch)
      end
    end

    # BR-064: el flujo es exclusivamente pending_payment → paid → issued.
    # El admin NO puede crear, editar ni eliminar certificados.

    test "new route helper is not defined" do
      assert_not Rails.application.routes.url_helpers.respond_to?(:new_admin_residence_certificate_path)
    end

    test "create route is not recognized" do
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/admin/residence_certificates", method: :post)
      end
    end

    test "edit route is not recognized" do
      assert_not Rails.application.routes.url_helpers.respond_to?(:edit_admin_residence_certificate_path)
    end

    test "update route is not recognized" do
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/admin/residence_certificates/1", method: :patch)
      end
    end

    test "destroy route is not recognized" do
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/admin/residence_certificates/1", method: :delete)
      end
    end

    test "delete confirmation route is not recognized" do
      assert_not Rails.application.routes.url_helpers.respond_to?(:delete_admin_residence_certificate_path)
    end

    # --- Read-only access still works ---

    test "admin can view index" do
      sign_in @admin
      get admin_residence_certificates_url
      assert_response :success
      assert_match @cert.folio, @response.body
    end

    test "admin can view show" do
      sign_in @admin
      get admin_residence_certificate_url(@cert)
      assert_response :success
      assert_match @cert.folio, @response.body
    end
  end
end
