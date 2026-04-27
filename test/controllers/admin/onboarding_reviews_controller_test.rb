require "test_helper"

module Admin
  class OnboardingReviewsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @admin = users(:selendis)
      @karax = users(:karax)
      @onboarding_request = onboarding_requests(:karax_pending)
      @identity_request = identity_verification_requests(:karax_identity)
      @residence_request = residence_verification_requests(:karax_residence)
    end

    # --- Access Guards ---

    test "non-admin is redirected" do
      sign_in @karax
      get review_step1_admin_onboarding_request_url(@onboarding_request)
      assert_redirected_to root_url
    end

    test "cannot access review for non-pending request" do
      sign_in @admin
      @onboarding_request.update!(status: "approved")

      get review_step1_admin_onboarding_request_url(@onboarding_request)
      assert_redirected_to admin_onboarding_request_url(@onboarding_request)
    end

    # --- Step 1: Identity Review ---

    test "admin can view step1" do
      sign_in @admin
      get review_step1_admin_onboarding_request_url(@onboarding_request)
      assert_response :success
    end

    test "step1 shows continue button instead of approve" do
      sign_in @admin
      get review_step1_admin_onboarding_request_url(@onboarding_request)
      assert_response :success
      assert_select "a", text: I18n.t("admin.onboarding_reviews.step1.continue_button")
    end

    # --- Step 2: Residence Review ---

    test "admin can view step2" do
      sign_in @admin
      get review_step2_admin_onboarding_request_url(@onboarding_request)
      assert_response :success
    end

    test "step2 shows continue button instead of approve" do
      sign_in @admin
      get review_step2_admin_onboarding_request_url(@onboarding_request)
      assert_response :success
      assert_select "a", text: I18n.t("admin.onboarding_reviews.step2.continue_button")
    end

    # --- Step 3: Final Approval ---

    test "admin can view step3" do
      sign_in @admin
      get review_step3_admin_onboarding_request_url(@onboarding_request)
      assert_response :success
    end

    test "step3 shows update transitions when pre-existing identity found" do
      sign_in @admin

      # Create a pre-existing verified identity with the same RUN
      existing_identity = VerifiedIdentity.create!(
        run: @identity_request.run,
        first_name: "Karax Antiguo",
        last_name: "Khalai",
        phone: "+56911112222",
        email: "old@example.com"
      )

      # Give it an existing residency
      hu = household_units(:selendis_household)
      Residency.create!(
        verified_identity: existing_identity,
        verified_residence: hu.verified_residence,
        household_unit: hu,
        household_admin: false,
        status: "approved"
      )

      get review_step3_admin_onboarding_request_url(@onboarding_request)
      assert_response :success

      # Should show both transition cards with update badges
      assert_select "h3", text: I18n.t("admin.onboarding_reviews.step3.identity_transition")
      assert_select "h3", text: I18n.t("admin.onboarding_reviews.step3.residence_transition")
      assert_select "span", text: I18n.t("admin.onboarding_reviews.step3.current_residence")
      assert_select "span", text: I18n.t("admin.onboarding_reviews.step3.new_residence")
      assert_select ".alert-warning"
      # "Khalai" matches, "Karax Antiguo" -> "Karax" will update
      assert_select "span.badge", text: I18n.t("admin.onboarding_reviews.step3.match")
      assert_select "span.badge", text: I18n.t("admin.onboarding_reviews.step3.will_update")
    end

    test "step3 shows creation transitions when no pre-existing identity" do
      sign_in @admin

      get review_step3_admin_onboarding_request_url(@onboarding_request)
      assert_response :success

      # Transitions always shown — with creation badges for new identity
      assert_select "h3", text: I18n.t("admin.onboarding_reviews.step3.identity_transition")
      assert_select "h3", text: I18n.t("admin.onboarding_reviews.step3.residence_transition")
      assert_select ".alert-info"
      assert_select "p", text: I18n.t("admin.onboarding_reviews.step3.no_current_identity")
      assert_select "p", text: I18n.t("admin.onboarding_reviews.step3.no_current_residence")
      assert_select "span.badge", text: I18n.t("admin.onboarding_reviews.step3.will_create")
    end

    test "step3 shows matching household units when they exist" do
      sign_in @admin

      matching_hu = household_units(:matching_karax_household)

      get review_step3_admin_onboarding_request_url(@onboarding_request)
      assert_response :success

      # Should show radio buttons for matching unit and create new option
      assert_select "input[type=radio][name=household_unit_id][value='#{matching_hu.id}']"
      assert_select "input[type=radio][name=household_unit_id][value='new'][checked]"
    end

    test "step3 shows household units from identity's existing residencies" do
      sign_in @admin

      # Delete the address-matching fixture so only identity-based match remains
      household_units(:matching_karax_household).destroy

      # Create a pre-existing verified identity with the same RUN
      existing_identity = VerifiedIdentity.create!(
        run: @identity_request.run,
        first_name: "Karax",
        last_name: "Khalai",
        phone: "+56977778888",
        email: "karax@example.com"
      )

      # Create a residency for it in a different HU
      other_hu = household_units(:selendis_household)
      Residency.create!(
        verified_identity: existing_identity,
        verified_residence: other_hu.verified_residence,
        household_unit: other_hu,
        household_admin: false,
        status: "approved"
      )

      get review_step3_admin_onboarding_request_url(@onboarding_request)
      assert_response :success

      # Should show the HU from the identity's existing residency
      assert_select "input[type=radio][name=household_unit_id][value='#{other_hu.id}']"
    end

    test "step3 does not show matching section when no matches exist" do
      sign_in @admin

      # Delete the address-matching fixture so no matches are found
      household_units(:matching_karax_household).destroy

      get review_step3_admin_onboarding_request_url(@onboarding_request)
      assert_response :success

      # Should not show radio buttons
      assert_select "input[type=radio][name=household_unit_id]", count: 0
    end

    test "approve_step3 creates all records" do
      sign_in @admin

      assert_difference -> { VerifiedIdentity.count }, 1 do
        assert_difference -> { VerifiedResidence.count }, 1 do
          assert_difference -> { HouseholdUnit.count }, 1 do
            assert_difference -> { Residency.count }, 1 do
              assert_difference -> { Member.count }, 1 do
                patch review_step3_admin_onboarding_request_url(@onboarding_request)
              end
            end
          end
        end
      end

      assert_redirected_to admin_onboarding_request_url(@onboarding_request)

      @onboarding_request.reload
      assert @onboarding_request.approved?

      # Verify identity request was approved
      @identity_request.reload
      assert @identity_request.approved?

      # Verify VerifiedIdentity was created and linked
      @karax.reload
      assert_not_nil @karax.verified_identity
      assert_equal "Karax", @karax.verified_identity.first_name
      assert_equal "Khalai", @karax.verified_identity.last_name
      assert_equal @identity_request.run, @karax.verified_identity.run
      assert_equal @identity_request, @karax.verified_identity.identity_verification_request

      # Verify residence request was approved
      @residence_request.reload
      assert @residence_request.approved?

      # Verify VerifiedResidence was created
      verified_residence = VerifiedResidence.find_by(residence_verification_request: @residence_request)
      assert_not_nil verified_residence
      assert_equal @residence_request.number, verified_residence.number
      assert_equal @onboarding_request.neighborhood_association, verified_residence.neighborhood_association

      # Verify user linked to neighborhood association
      assert_equal @onboarding_request.neighborhood_association, @karax.neighborhood_association

      # Verify household unit linked to verified residence
      household_unit = HouseholdUnit.last
      assert_equal verified_residence, household_unit.verified_residence

      # Verify residency was created
      residency = Residency.last
      assert residency.approved?
      assert residency.household_admin?
      assert_equal household_unit, residency.household_unit
      assert_equal @karax.verified_identity, residency.verified_identity

      # Verify member was created (association membership)
      member = Member.last
      assert member.approved?
      assert_equal @admin, member.approved_by
      assert_equal @karax.verified_identity, member.verified_identity
      assert_equal @onboarding_request.neighborhood_association, member.neighborhood_association
    end

    test "approve_step3 relinks existing household unit when selected" do
      sign_in @admin

      existing_hu = household_units(:matching_karax_household)

      assert_no_difference -> { HouseholdUnit.count } do
        assert_difference -> { Residency.count }, 1 do
          assert_difference -> { Member.count }, 1 do
            patch review_step3_admin_onboarding_request_url(@onboarding_request),
              params: { household_unit_id: existing_hu.id }
          end
        end
      end

      assert_redirected_to admin_onboarding_request_url(@onboarding_request)

      @onboarding_request.reload
      assert @onboarding_request.approved?

      # Verify existing HU was relinked to the new verified residence
      existing_hu.reload
      verified_residence = VerifiedResidence.find_by(residence_verification_request: @residence_request)
      assert_equal verified_residence, existing_hu.verified_residence

      # Verify residency is linked to the existing HU
      residency = Residency.last
      assert residency.approved?
      assert residency.household_admin?
      assert_equal existing_hu, residency.household_unit
    end

    test "approve_step3 with household_unit_id=new creates new unit" do
      sign_in @admin

      assert_difference -> { HouseholdUnit.count }, 1 do
        assert_difference -> { Member.count }, 1 do
          patch review_step3_admin_onboarding_request_url(@onboarding_request),
            params: { household_unit_id: "new" }
        end
      end

      assert_redirected_to admin_onboarding_request_url(@onboarding_request)
      @onboarding_request.reload
      assert @onboarding_request.approved?
    end

    test "approve_step3 updates pre-existing identity instead of creating new" do
      sign_in @admin

      # Create a pre-existing verified identity with the same RUN
      existing_identity = VerifiedIdentity.create!(
        run: @identity_request.run,
        first_name: "Karax Antiguo",
        last_name: "Otro Apellido",
        phone: "+56911112222",
        email: "old@example.com"
      )

      assert_no_difference -> { VerifiedIdentity.count } do
        patch review_step3_admin_onboarding_request_url(@onboarding_request)
      end

      # Verify identity was updated with new data
      existing_identity.reload
      assert_equal "Karax", existing_identity.first_name
      assert_equal "Khalai", existing_identity.last_name
      assert_equal @identity_request.phone, existing_identity.phone
      assert_equal @karax.email, existing_identity.email

      # Verify user is linked to the existing identity
      @karax.reload
      assert_equal existing_identity, @karax.verified_identity
    end

    # --- Reject ---

    test "admin can reject request with reason" do
      sign_in @admin

      patch review_reject_admin_onboarding_request_url(@onboarding_request),
        params: { rejection_reason: "Documentos ilegibles" }

      assert_redirected_to admin_onboarding_request_url(@onboarding_request)

      @onboarding_request.reload
      assert @onboarding_request.rejected?
      assert_equal "Documentos ilegibles", @onboarding_request.rejection_reason

      @identity_request.reload
      assert @identity_request.rejected?

      @residence_request.reload
      assert @residence_request.rejected?
    end

    # --- Show page review link ---

    test "show page displays review link for pending requests" do
      sign_in @admin
      get admin_onboarding_request_url(@onboarding_request)
      assert_response :success
      assert_select "a", text: I18n.t("admin.onboarding_reviews.show.start_review")
    end

    test "show page does not display review link for approved requests" do
      sign_in @admin
      @onboarding_request.update!(status: "approved")

      get admin_onboarding_request_url(@onboarding_request)
      assert_response :success
      assert_select "a", text: I18n.t("admin.onboarding_reviews.show.start_review"), count: 0
    end
  end
end
