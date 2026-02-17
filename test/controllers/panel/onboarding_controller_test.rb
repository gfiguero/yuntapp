require "test_helper"

module Panel
  class OnboardingControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @urunis = users(:urunis)           # no onboarding request, no member
      @karass = users(:karass)           # has pending onboarding_request fixture
      @selendis = users(:selendis)       # has verified_identity + member (approved)
      @association = neighborhood_associations(:association_0)
      @delegation = neighborhood_delegations(:neighborhood_delegation_0_0)
      @region = @association.commune.region
      @commune = @association.commune
    end

    # --- dashboard ---

    test "new user can access dashboard" do
      sign_in @urunis
      get panel_root_url
      assert_response :success
    end

    # --- step1 ---

    test "step1 renders region select" do
      sign_in @urunis
      get panel_onboarding_step1_url
      assert_response :success
      assert_select "select[name='region_id']"
    end

    test "update_step1 with commit_continue and all selectors redirects to step2" do
      sign_in @urunis
      get panel_onboarding_step1_url

      patch panel_onboarding_step1_url, params: {
        commit_continue: "Continuar",
        region_id: @region.id,
        commune_id: @commune.id,
        neighborhood_association_id: @association.id
      }
      assert_redirected_to panel_onboarding_step2_url
    end

    test "update_step1 without commit_continue does not redirect" do
      sign_in @urunis
      get panel_onboarding_step1_url

      patch panel_onboarding_step1_url, params: {
        region_id: @region.id
      }
      # Should render turbo_stream or html, not redirect
      assert_response :success
    end

    # --- ensure_step1 ---

    test "step2 without completing step1 redirects to step1" do
      sign_in @urunis
      get panel_onboarding_step2_url
      assert_redirected_to panel_onboarding_step1_url
    end

    test "step2 with session but no association redirects to step1" do
      sign_in @urunis
      # Visit step1 to create OnboardingRequest (without association)
      get panel_onboarding_step1_url
      # Don't complete step1 (no PATCH with association), go directly to step2
      get panel_onboarding_step2_url
      assert_redirected_to panel_onboarding_step1_url
    end

    # --- step2 ---

    test "step2 renders identity form after completing step1" do
      sign_in @urunis
      complete_step1

      get panel_onboarding_step2_url
      assert_response :success
    end

    test "update_step2 autosave saves field without redirect" do
      sign_in @urunis
      complete_step1
      get panel_onboarding_step2_url

      patch panel_onboarding_step2_url, params: {
        identity_verification_request: {first_name: "Test"}
      }
      # Autosave responds with turbo_stream or html, not redirect
      assert_response :success
    end

    # --- ensure_step2 ---

    test "step3 without completing step2 redirects to step2" do
      sign_in @urunis
      complete_step1
      get panel_onboarding_step3_url
      assert_redirected_to panel_onboarding_step2_url
    end

    # --- step4 guards ---

    test "step4 without any steps redirects to step1" do
      sign_in @urunis
      get panel_onboarding_step4_url
      assert_redirected_to panel_onboarding_step1_url
    end

    # --- user with member is redirected away from onboarding ---

    test "user with member is redirected from onboarding to dashboard" do
      sign_in @selendis
      get panel_onboarding_step1_url
      assert_redirected_to panel_root_url
    end

    private

    def complete_step1
      get panel_onboarding_step1_url
      patch panel_onboarding_step1_url, params: {
        commit_continue: "Continuar",
        region_id: @region.id,
        commune_id: @commune.id,
        neighborhood_association_id: @association.id
      }
    end
  end
end
