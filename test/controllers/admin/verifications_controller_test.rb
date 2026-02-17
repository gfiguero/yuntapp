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

    test "admin can view pending verifications" do
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

    # --- approve ---

    test "admin can approve a pending verification" do
      sign_in @selendis

      assert @rohana_verified_identity.pending_verification?

      patch approve_admin_verification_url(@rohana_verified_identity)

      assert_redirected_to admin_verification_url(@rohana_verified_identity)
      @rohana_verified_identity.reload
      assert @rohana_verified_identity.verified?
    end

    # --- reject ---

    test "admin can reject a pending verification" do
      sign_in @selendis

      patch reject_admin_verification_url(@rohana_verified_identity)

      assert_redirected_to admin_verification_url(@rohana_verified_identity)
      @rohana_verified_identity.reload
      assert @rohana_verified_identity.rejected_verification?
    end

    # --- auto-link on approve ---

    test "approving verified identity makes user automatically see their member" do
      sign_in @selendis

      # Create a member linked to rohana's verified identity
      member = Member.create!(
        household_unit: household_units(:selendis_household),
        verified_identity: @rohana_verified_identity,
        status: "approved"
      )

      # Before approve, rohana's verified identity is pending — user still sees member via verified_identity
      assert_equal member, @rohana.member

      patch approve_admin_verification_url(@rohana_verified_identity)

      @rohana_verified_identity.reload
      assert @rohana_verified_identity.verified?
      # Member is accessible via verified_identity
      assert_equal member, @rohana.reload.member
    end
  end
end
