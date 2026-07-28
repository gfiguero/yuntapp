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

    # --- Transición household_admin → dependiente (BR-095/BR-096/BR-097, ADR-006) ---

    test "approve deactivates the prior household_admin membership with the same RUN and cascades" do
      sign_in @admin

      # El solicitante entrante es un household_admin ya activo (selendis) que gestiona a
      # un dependiente (vorazun), y ahora se registra como dependiente en OTRO domicilio.
      selendis_identity = verified_identities(:selendis_persona)
      prior_admin_member = members(:selendis_member)
      cascaded_dependent = members(:dependent_member)
      assert prior_admin_member.approved?
      assert cascaded_dependent.approved?

      # Domicilio destino nuevo (distinto al de selendis, para no chocar en residencies).
      src_hu = household_units(:selendis_household)
      target_vr = VerifiedResidence.create!(neighborhood_association: @neighborhood_association)
      target_hu = HouseholdUnit.create!(
        neighborhood_delegation: src_hu.neighborhood_delegation,
        commune: src_hu.commune,
        number: "999"
      )
      target_fg = FamilyGroup.create!(household_unit: target_hu)
      # #94/BR-067: el dependiente hereda la VerifiedResidence del household_admin
      # de su FamilyGroup. El group destino debe tener un household_admin con residencia.
      target_admin_identity = VerifiedIdentity.create!(
        first_name: "Artanis", last_name: "Hierarch", run: "19000001-K", phone: "+56922222222"
      )
      Residency.create!(
        verified_identity: target_admin_identity,
        verified_residence: target_vr,
        household_unit: target_hu,
        family_group: target_fg,
        household_admin: true,
        status: "approved"
      )
      @dependent_request.update!(run: selendis_identity.run, family_group: target_fg)

      patch approve_admin_dependent_review_url(@dependent_request)

      prior_admin_member.reload
      cascaded_dependent.reload
      assert prior_admin_member.inactive?, "el household_admin anterior debe quedar inactive (BR-095)"
      assert cascaded_dependent.inactive?, "sus dependientes deben quedar inactive en cascada (BR-096)"
      assert prior_admin_member.deactivation_reason.present?

      # La nueva membresía dependiente queda aprobada
      new_member = Member.where(verified_identity: selendis_identity, dependent: true, status: "approved").last
      assert_not_nil new_member
    end

    test "approve does not deactivate anything when the RUN has no prior membership" do
      sign_in @admin

      # @dependent_request usa un RUN nuevo (77777777-7) sin membresías previas.
      assert_no_difference -> { Member.where(status: "inactive").count } do
        patch approve_admin_dependent_review_url(@dependent_request)
      end
    end

    test "approve aborts with alert when family_group has no household_admin (#94 guard)" do
      sign_in @admin
      orphan_fg = FamilyGroup.create!(household_unit: household_units(:selendis_household))
      orphan_request = IdentityVerificationRequest.create!(
        first_name: "Huerfano", last_name: "Sinjefe", run: "7000002-4",
        status: "pending", dependent: true, family_group: orphan_fg,
        requested_by: users(:karass), neighborhood_association: @neighborhood_association
      )

      assert_no_difference -> { Residency.count } do
        assert_no_difference -> { Member.count } do
          patch approve_admin_dependent_review_url(orphan_request)
        end
      end

      assert_redirected_to admin_dependent_reviews_path
      assert_equal "pending", orphan_request.reload.status
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
