require "test_helper"

module Admin
  class VerificationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @selendis = users(:selendis)
      @rohana = users(:rohana)
      @rohana_verified_identity = verified_identities(:rohana_persona)

      # Link rohana to the same neighborhood association as selendis
      @rohana.update!(
        neighborhood_association: @selendis.neighborhood_association,
        verified_identity: @rohana_verified_identity
      )
    end

    # --- index ---

    test "admin can view verifications" do
      sign_in @selendis
      get admin_verifications_url
      assert_response :success
    end

    test "non-admin is redirected" do
      sign_in @rohana
      get admin_verifications_url
      assert_redirected_to root_url
    end

    # --- show ---

    test "admin can view verification detail" do
      sign_in @selendis
      get admin_verification_url(@rohana_verified_identity)
      assert_response :success
    end
  end
end
