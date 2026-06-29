require "test_helper"

module Admin
  class ResidenceCertificatesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @admin = users(:selendis)
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
  end
end
