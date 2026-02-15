require "test_helper"

module Admin
  class VerificationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @selendis = users(:selendis)
      @rohana = users(:rohana)
      @rohana_persona = personas(:rohana_persona)

      # Link rohana to the same neighborhood association as selendis
      @rohana.update!(
        neighborhood_association: @selendis.neighborhood_association,
        persona: @rohana_persona
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
      get admin_verification_url(@rohana_persona)
      assert_response :success
    end

    # --- approve ---

    test "admin can approve a pending verification" do
      sign_in @selendis

      assert @rohana_persona.pending_verification?

      patch approve_admin_verification_url(@rohana_persona)

      assert_redirected_to admin_verification_url(@rohana_persona)
      @rohana_persona.reload
      assert @rohana_persona.verified?
    end

    # --- reject ---

    test "admin can reject a pending verification" do
      sign_in @selendis

      patch reject_admin_verification_url(@rohana_persona)

      assert_redirected_to admin_verification_url(@rohana_persona)
      @rohana_persona.reload
      assert @rohana_persona.rejected_verification?
    end

    # --- auto-link on approve ---

    test "approving persona makes user automatically see their member" do
      sign_in @selendis

      # Create a member linked to rohana's persona
      member = Member.create!(
        household_unit: household_units(:selendis_household),
        persona: @rohana_persona,
        status: "approved"
      )

      # Before approve, rohana's persona is pending — user still sees member via persona
      assert_equal member, @rohana.member

      patch approve_admin_verification_url(@rohana_persona)

      @rohana_persona.reload
      assert @rohana_persona.verified?
      # Member is accessible via persona
      assert_equal member, @rohana.reload.member
    end
  end
end
