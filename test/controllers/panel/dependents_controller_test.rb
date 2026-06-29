require "test_helper"

module Panel
  class DependentsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @household_admin = users(:selendis)
      @non_admin = users(:karass)
      @family_group = family_groups(:selendis_family_group)
      @neighborhood_association = neighborhood_associations(:manios_de_buin)
    end

    # --- Authorization ---

    test "redirects when user is not household_admin" do
      sign_in @non_admin
      get panel_dependents_url
      assert_redirected_to panel_root_url
    end

    test "redirects when user is not signed in" do
      get panel_dependents_url
      assert_redirected_to new_user_session_url
    end

    test "household_admin can view index" do
      sign_in @household_admin
      get panel_dependents_url
      assert_response :success
    end

    test "household_admin can view new form" do
      sign_in @household_admin
      get new_panel_dependent_url
      assert_response :success
    end

    # --- Create ---

    test "household_admin can create a pending dependent request" do
      sign_in @household_admin

      assert_difference -> { IdentityVerificationRequest.count }, 1 do
        post panel_dependents_url, params: {
          identity_verification_request: {
            first_name: "Aiur",
            last_name: "Daelaam",
            run: "88888888-8",
            phone: ""
          }
        }
      end

      ivr = IdentityVerificationRequest.order(:created_at).last
      assert ivr.dependent?
      assert ivr.pending?
      assert_equal @family_group, ivr.family_group
      assert_equal @household_admin, ivr.requested_by
      assert_equal @neighborhood_association, ivr.neighborhood_association
      assert_nil ivr.user
      assert_redirected_to panel_dependents_url
    end

    test "create rejects invalid RUN" do
      sign_in @household_admin

      assert_no_difference -> { IdentityVerificationRequest.count } do
        post panel_dependents_url, params: {
          identity_verification_request: {
            first_name: "Aiur",
            last_name: "Daelaam",
            run: "invalid",
            phone: ""
          }
        }
      end

      assert_response :unprocessable_content
    end

    test "create ignores attempts to set dependent flag via params" do
      sign_in @household_admin

      post panel_dependents_url, params: {
        identity_verification_request: {
          first_name: "Aiur",
          last_name: "Daelaam",
          run: "88888888-8",
          dependent: false,
          family_group_id: 99999,
          requested_by_id: 99999,
          neighborhood_association_id: 99999,
          status: "approved"
        }
      }

      ivr = IdentityVerificationRequest.order(:created_at).last
      assert ivr.dependent?
      assert ivr.pending?
      assert_equal @family_group, ivr.family_group
      assert_equal @household_admin, ivr.requested_by
      assert_equal @neighborhood_association, ivr.neighborhood_association
    end

    # --- Index scoping ---

    test "index shows only dependents from current family_group" do
      sign_in @household_admin

      our = identity_verification_requests(:selendis_dependent_identity)
      other_family_group = FamilyGroup.create!(household_unit: household_units(:matching_karax_household))
      foreign = IdentityVerificationRequest.create!(
        first_name: "Foreign",
        last_name: "Child",
        run: "99999999-9",
        status: "pending",
        dependent: true,
        family_group: other_family_group,
        requested_by: users(:karass),
        neighborhood_association: @neighborhood_association
      )

      get panel_dependents_url
      assert_response :success
      assert_match our.full_name, @response.body
      assert_no_match(/#{foreign.full_name}/, @response.body)
    end
  end
end
