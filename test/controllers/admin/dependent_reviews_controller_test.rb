require "test_helper"

module Admin
  class DependentReviewsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @admin = users(:selendis)
      @non_admin = users(:karass)
      @dependent_request = identity_verification_requests(:selendis_dependent_identity)
      @family_group = family_groups(:selendis_family_group)
      @neighborhood_association = neighborhood_associations(:manios_de_buin)
    end

    # --- Authorization ---

    test "non-admin is redirected" do
      sign_in @non_admin
      get admin_dependent_reviews_url
      assert_redirected_to root_url
    end

    test "unauthenticated is redirected to login" do
      get admin_dependent_reviews_url
      assert_redirected_to new_user_session_url
    end

    test "admin can view index" do
      sign_in @admin
      get admin_dependent_reviews_url
      assert_response :success
      assert_match @dependent_request.full_name, @response.body
    end

    test "admin can view show" do
      sign_in @admin
      get admin_dependent_review_url(@dependent_request)
      assert_response :success
    end

    # --- Multi-tenant isolation ---

    test "admin sees only dependents from own neighborhood_association" do
      sign_in @admin

      other_association = neighborhood_associations(:association_1)
      other_family_group = FamilyGroup.create!(household_unit: household_units(:matching_karax_household))
      IdentityVerificationRequest.create!(
        first_name: "Foreign",
        last_name: "Child",
        run: "99999999-9",
        status: "pending",
        dependent: true,
        family_group: other_family_group,
        requested_by: users(:karass),
        neighborhood_association: other_association
      )

      get admin_dependent_reviews_url
      assert_response :success
      assert_match @dependent_request.full_name, @response.body
      assert_no_match(/Foreign/, @response.body)
    end

    test "admin cannot view show for foreign neighborhood_association" do
      sign_in @admin
      other_association = neighborhood_associations(:association_1)
      other_family_group = FamilyGroup.create!(household_unit: household_units(:matching_karax_household))
      foreign_request = IdentityVerificationRequest.create!(
        first_name: "Foreign",
        last_name: "Child",
        run: "99999999-9",
        status: "pending",
        dependent: true,
        family_group: other_family_group,
        requested_by: users(:karass),
        neighborhood_association: other_association
      )

      get admin_dependent_review_url(foreign_request)
      assert_response :not_found
    end

    # --- Approve ---

    test "approve creates VerifiedIdentity, Member(dependent), Residency(non admin) in transaction" do
      sign_in @admin

      assert_difference -> { VerifiedIdentity.count }, 1 do
        assert_difference -> { Member.count }, 1 do
          assert_difference -> { Residency.count }, 1 do
            patch approve_admin_dependent_review_url(@dependent_request)
          end
        end
      end

      @dependent_request.reload
      assert @dependent_request.approved?

      verified_identity = VerifiedIdentity.find_by(run: @dependent_request.run)
      assert_not_nil verified_identity
      assert_equal @dependent_request.first_name, verified_identity.first_name
      assert_equal @dependent_request, verified_identity.identity_verification_request

      member = Member.find_by(verified_identity: verified_identity)
      assert_not_nil member
      assert member.dependent?
      assert member.approved?
      assert_equal @neighborhood_association, member.neighborhood_association
      assert_equal @admin, member.approved_by
      assert_equal @admin, member.requested_by

      residency = Residency.find_by(verified_identity: verified_identity)
      assert_not_nil residency
      assert_not residency.household_admin?
      assert residency.approved?
      assert_equal @family_group, residency.family_group
      assert_equal @family_group.household_unit, residency.household_unit
    end

    test "approve redirects to index with success notice" do
      sign_in @admin
      patch approve_admin_dependent_review_url(@dependent_request)
      assert_redirected_to admin_dependent_reviews_url
    end

    test "approve fails if dependent_request is not pending" do
      sign_in @admin
      @dependent_request.update!(status: "approved")

      assert_no_difference -> { VerifiedIdentity.count } do
        patch approve_admin_dependent_review_url(@dependent_request)
      end
    end

    test "approve cannot be triggered for foreign neighborhood_association" do
      sign_in @admin
      other_association = neighborhood_associations(:association_1)
      other_family_group = FamilyGroup.create!(household_unit: household_units(:matching_karax_household))
      foreign_request = IdentityVerificationRequest.create!(
        first_name: "Foreign",
        last_name: "Child",
        run: "99999999-9",
        status: "pending",
        dependent: true,
        family_group: other_family_group,
        requested_by: users(:karass),
        neighborhood_association: other_association
      )

      assert_no_difference -> { Member.count } do
        patch approve_admin_dependent_review_url(foreign_request)
      end
      assert_response :not_found
    end

    # --- Reject ---

    test "reject sets status and rejection_reason" do
      sign_in @admin

      patch reject_admin_dependent_review_url(@dependent_request),
        params: {rejection_reason: "Documento ilegible"}

      @dependent_request.reload
      assert @dependent_request.rejected?
      assert_equal "Documento ilegible", @dependent_request.rejection_reason
      assert_redirected_to admin_dependent_reviews_url
    end

    test "reject does not create downstream records" do
      sign_in @admin

      assert_no_difference -> { VerifiedIdentity.count } do
        assert_no_difference -> { Member.count } do
          assert_no_difference -> { Residency.count } do
            patch reject_admin_dependent_review_url(@dependent_request),
              params: {rejection_reason: "test"}
          end
        end
      end
    end
  end
end
