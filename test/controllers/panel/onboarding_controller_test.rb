require "test_helper"

module Panel
  class OnboardingControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @karass = users(:karass)           # no persona, no member
      @selendis = users(:selendis)       # has persona (verified) + member (approved)
      @rohana = users(:rohana)           # no persona linked to user, no member
      @association = neighborhood_associations(:association_0)
      @delegation = neighborhood_delegations(:neighborhood_delegation_0_0)
    end

    # --- redirect from dashboard ---

    test "new user is redirected from dashboard to onboarding step1" do
      sign_in @karass
      get panel_root_url
      assert_redirected_to panel_onboarding_step1_url
    end

    test "user with member is NOT redirected from dashboard" do
      sign_in @selendis
      get panel_root_url
      assert_response :success
    end

    # --- step1 ---

    test "step1 renders cascading selects for region, commune and association" do
      sign_in @karass
      get panel_onboarding_step1_url
      assert_response :success
      assert_select "[data-cascading-select-target='region']"
      assert_select "[data-cascading-select-target='commune']"
      assert_select "[data-cascading-select-target='association']"
      assert_select "input[name='neighborhood_association_id']"
    end

    test "update_step1 saves association in session and redirects to step2" do
      sign_in @karass
      patch panel_onboarding_step1_url, params: {neighborhood_association_id: @association.id}
      assert_redirected_to panel_onboarding_step2_url
    end

    # --- step2 ---

    test "step2 without step1 redirects to step1" do
      sign_in @karass
      get panel_onboarding_step2_url
      assert_redirected_to panel_onboarding_step1_url
    end

    test "step2 renders household unit form" do
      sign_in @karass
      patch panel_onboarding_step1_url, params: {neighborhood_association_id: @association.id}
      get panel_onboarding_step2_url
      assert_response :success
    end

    test "update_step2 creates household unit and redirects to step3" do
      sign_in @karass
      patch panel_onboarding_step1_url, params: {neighborhood_association_id: @association.id}

      assert_difference("HouseholdUnit.count", 1) do
        patch panel_onboarding_step2_url, params: {household_unit: {
          neighborhood_delegation_id: @delegation.id,
          number: "Casa 42"
        }}
      end

      assert_redirected_to panel_onboarding_step3_url
    end

    # --- step3 ---

    test "step3 without step2 redirects to step2" do
      sign_in @karass
      patch panel_onboarding_step1_url, params: {neighborhood_association_id: @association.id}
      get panel_onboarding_step3_url
      assert_redirected_to panel_onboarding_step2_url
    end

    test "step3 renders identity form" do
      sign_in @karass
      complete_steps_1_and_2(@karass)
      get panel_onboarding_step3_url
      assert_response :success
    end

    test "update_step3 creates persona and redirects to step4" do
      sign_in @karass
      complete_steps_1_and_2(@karass)

      assert_difference("VerifiedIdentity.count", 1) do
        patch panel_onboarding_step3_url, params: {verified_identity: {
          first_name: "Karass",
          last_name: "Templar",
          run: "77.777.777-7",
          phone: "+56912345678"
        }}
      end

      assert_redirected_to panel_onboarding_step4_url
      @karass.reload
      assert_not_nil @karass.verified_identity
      assert_equal "pending", @karass.verified_identity.verification_status
    end

    test "step3 with verified persona redirects to step4" do
      # Give rohana a verified persona and complete steps 1-2
      rohana_persona = verified_identities(:rohana_persona)
      rohana_persona.update!(verification_status: "verified")
      @rohana.update!(verified_identity: rohana_persona)

      sign_in @rohana
      complete_steps_1_and_2(@rohana)
      get panel_onboarding_step3_url
      assert_redirected_to panel_onboarding_step4_url
    end

    test "update_step3 rejects RUN already claimed by another user" do
      sign_in @karass
      complete_steps_1_and_2(@karass)

      # selendis_persona run 11111111-1 is already linked to selendis
      patch panel_onboarding_step3_url, params: {verified_identity: {
        first_name: "Fake",
        last_name: "Person",
        run: "111111111",
        phone: "+56900000000"
      }}

      assert_redirected_to panel_onboarding_step3_url
      assert_equal I18n.t("persona.message.run_already_claimed"), flash[:alert]
    end

    # --- step4 ---

    test "step4 without step3 redirects to step3" do
      sign_in @karass
      complete_steps_1_and_2(@karass)
      get panel_onboarding_step4_url
      assert_redirected_to panel_onboarding_step3_url
    end

    test "step4 shows summary" do
      sign_in @karass
      complete_all_steps(@karass)
      get panel_onboarding_step4_url
      assert_response :success
      assert_select ".card", minimum: 3
    end

    # --- submit ---

    test "submit creates pending member and clears session" do
      sign_in @karass
      complete_all_steps(@karass)

      assert_difference("Member.count", 1) do
        post panel_onboarding_submit_url
      end

      assert_redirected_to panel_root_url
      assert_equal I18n.t("onboarding.message.completed"), flash[:notice]

      member = Member.last
      assert_equal "pending", member.status
      assert_equal @karass.reload.verified_identity, member.verified_identity
      assert_equal @karass, member.requested_by
    end

    # --- user with member is redirected away from onboarding ---

    test "user with member is redirected from onboarding to dashboard" do
      sign_in @selendis
      get panel_onboarding_step1_url
      assert_redirected_to panel_root_url
    end

    private

    def complete_steps_1_and_2(user)
      patch panel_onboarding_step1_url, params: {neighborhood_association_id: @association.id}
      patch panel_onboarding_step2_url, params: {household_unit: {
        neighborhood_delegation_id: @delegation.id,
        number: "Casa 42"
      }}
    end

    def complete_all_steps(user)
      complete_steps_1_and_2(user)
      patch panel_onboarding_step3_url, params: {verified_identity: {
        first_name: "Karass",
        last_name: "Templar",
        run: "77.777.777-7",
        phone: "+56912345678"
      }}
    end
  end
end
