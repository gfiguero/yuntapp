require "test_helper"

module Panel
  class AccreditationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @selendis = users(:selendis)
      @karass = users(:karass)
      @selendis_household = household_units(:selendis_household)
      @selendis_member = members(:selendis_member)
      @karass_dependent = members(:karass_dependent)
      @karass_persona = verified_identities(:karass_persona)
    end

    # --- Fixture sanity checks ---

    test "selendis has persona, member, and household_unit via member" do
      assert @selendis.verified_identity.verified?
      assert @selendis_member.approved?
      assert @selendis_member.household_admin?
      assert_equal @selendis, @selendis_member.user
      assert_equal @selendis_household, @selendis.household_unit
    end

    test "karass_dependent is approved, linked to karass_persona" do
      assert @karass_dependent.approved?
      assert_equal @karass_persona, @karass_dependent.verified_identity
    end

    test "selendis household has multiple approved dependents" do
      approved = @selendis_household.members.approved
      assert approved.count >= 4, "Expected at least 4 approved members (selendis + 3 dependents)"
    end

    # --- Verification prerequisite ---

    test "unverified user is redirected to verification on new" do
      sign_in @karass
      assert_not @karass.verified?

      get new_panel_accreditation_url
      assert_redirected_to new_panel_verification_url
      assert_equal I18n.t("panel.verification.flash.must_verify_first"), flash[:alert]
    end

    test "unverified user is redirected to verification on create" do
      sign_in @karass
      assert_not @karass.verified?

      post panel_accreditation_url, params: {member: {documents: []}}
      assert_redirected_to new_panel_verification_url
    end

    # --- Auto-linking by Persona ---

    test "karass auto-links when persona has existing member" do
      # When karass verifies with karass_persona (which has karass_dependent member),
      # current_user.member returns karass_dependent automatically via persona
      @karass_persona.update!(verification_status: "verified")
      @karass.update!(verified_identity: @karass_persona)
      sign_in @karass

      # karass now has a member via persona (karass_dependent)
      assert_not_nil @karass.member
      assert_equal @karass_dependent, @karass.member

      get new_panel_accreditation_url
      assert_redirected_to panel_accreditation_url
    end

    test "auto-linked user can see their accreditation" do
      @karass_persona.update!(verification_status: "verified")
      @karass.update!(verified_identity: @karass_persona)
      sign_in @karass

      get panel_accreditation_url
      assert_response :success
    end

    # --- Normal flow: verified user, no existing member, with household_unit ---

    test "creates pending member for verified user with household_unit" do
      persona = VerifiedIdentity.create!(first_name: "Karass", last_name: "New", run: "88888888-8", verification_status: "verified")
      @karass.update!(verified_identity: persona)

      # Create household unit and store it in session
      sign_in @karass
      post panel_household_units_url, params: {household_unit: {
        number: "Test #1",
        neighborhood_delegation: household_units(:selendis_household).neighborhood_delegation.id
      }.merge(neighborhood_delegation_id: household_units(:selendis_household).neighborhood_delegation.id)}

      assert_difference("Member.count", 1) do
        post panel_accreditation_url, params: {member: {documents: []}}
      end

      assert_redirected_to panel_accreditation_url
      assert_equal I18n.t("panel.accreditations.flash.requested"), flash[:notice]

      new_member = Member.last
      assert_equal "pending", new_member.status
      assert_equal persona, new_member.verified_identity
      assert_equal "Karass", new_member.first_name
      assert_equal "88888888-8", new_member.run
    end

    # --- Error: no match and no household_unit ---

    test "redirects with error when verified user has no household_unit" do
      persona = VerifiedIdentity.create!(first_name: "Karass", last_name: "New", run: "88888888-8", verification_status: "verified")
      @karass.update!(verified_identity: persona)
      sign_in @karass

      assert_nil @karass.household_unit

      assert_no_difference("Member.count") do
        post panel_accreditation_url, params: {member: {documents: []}}
      end

      assert_redirected_to new_panel_household_unit_url
      assert_equal I18n.t("panel.accreditations.flash.run_not_found_no_household"), flash[:alert]
    end

    # --- new action accessible for verified user ---

    test "verified user without existing member can access new accreditation form" do
      persona = VerifiedIdentity.create!(first_name: "Karass", last_name: "New", run: "88888888-8", verification_status: "verified")
      @karass.update!(verified_identity: persona)
      sign_in @karass

      get new_panel_accreditation_url
      assert_response :success
    end

    # --- Edge cases ---

    test "redirects to show if user already has a member" do
      sign_in @selendis

      get new_panel_accreditation_url
      assert_redirected_to panel_accreditation_url

      post panel_accreditation_url, params: {member: {documents: []}}
      assert_redirected_to panel_accreditation_url
    end
  end
end
