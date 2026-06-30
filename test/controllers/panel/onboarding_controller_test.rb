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

    test "user with approved member is redirected from onboarding to dashboard" do
      sign_in @selendis
      get panel_onboarding_step1_url
      assert_redirected_to panel_root_url
    end

    test "user with inactive member can access onboarding" do
      members(:selendis_member).update!(status: "inactive", deactivation_reason: "Test deactivation")
      sign_in @selendis
      get panel_onboarding_step1_url
      assert_response :success
    end

    # --- restart sets member to inactive ---

    test "restart sets member to inactive instead of destroying it" do
      sign_in @selendis
      member = members(:selendis_member)
      assert member.approved?

      delete panel_onboarding_restart_url
      assert_redirected_to panel_onboarding_step1_url

      assert member.reload.inactive?
    end

    # --- cancel (BR-051) ---

    test "cancel transitions pending OR to cancelled and redirects to dashboard" do
      sign_in @karass
      onboarding = @karass.current_onboarding_request
      assert onboarding.pending?

      delete panel_onboarding_cancel_url

      onboarding.reload
      assert onboarding.cancelled?
      assert_redirected_to panel_root_url
      assert_equal I18n.t("panel.onboarding.flash.cancelled"), flash[:notice]
    end

    test "cancel cascades to IVR and RVR" do
      sign_in @karass
      onboarding = @karass.current_onboarding_request
      identity = onboarding.identity_verification_request
      residence = onboarding.residence_verification_request

      delete panel_onboarding_cancel_url

      identity.reload
      residence.reload
      assert_equal "cancelled", identity.status
      assert_equal "cancelled", residence.status
    end

    test "cancel refuses when user has no pending onboarding" do
      sign_in @urunis
      delete panel_onboarding_cancel_url
      assert_redirected_to panel_root_url
      assert_equal I18n.t("panel.onboarding.flash.cannot_cancel"), flash[:alert]
    end

    test "cancel refuses when onboarding is in draft" do
      sign_in @urunis
      OnboardingRequest.create!(user: @urunis, status: "draft")
      delete panel_onboarding_cancel_url
      assert_redirected_to panel_root_url
      assert_equal I18n.t("panel.onboarding.flash.cannot_cancel"), flash[:alert]
    end

    test "cancel allows user to start a new onboarding via step1" do
      sign_in @karass
      delete panel_onboarding_cancel_url

      get panel_onboarding_step1_url
      assert_response :success
      new_onboarding = @karass.reload.current_onboarding_request
      assert_not_nil new_onboarding
      assert new_onboarding.draft?
    end

    test "restart preserves member record in database" do
      sign_in @selendis
      member_id = members(:selendis_member).id

      delete panel_onboarding_restart_url

      assert Member.exists?(member_id), "Member should not be destroyed"
    end

    # --- update_step2 — file attachments + RUN validation ---

    test "update_step2 attaches identity_documents when present" do
      sign_in @urunis
      complete_step1
      get panel_onboarding_step2_url

      assert_difference -> { ActiveStorage::Attachment.count }, 1 do
        patch panel_onboarding_step2_url, params: {
          identity_verification_request: {
            identity_documents: [fixture_file_upload("id_placeholder.png", "image/png")]
          }
        }
      end

      ivr = @urunis.reload.current_onboarding_request.identity_verification_request
      assert ivr.identity_documents.attached?
    end

    test "update_step2 rejects RUN with invalid check digit" do
      sign_in @urunis
      complete_step1
      get panel_onboarding_step2_url

      patch panel_onboarding_step2_url, params: {
        identity_verification_request: {run: "11111111-9"}
      }
      # 422 cuando la validación de RUN falla (vs 200 con turbo_stream autosave en happy path)
      assert_response :unprocessable_content

      ivr = @urunis.reload.current_onboarding_request&.identity_verification_request
      # El RUN inválido no debe haberse persistido
      assert_not_equal "11111111-9", ivr&.run
    end

    test "delete_document removes a previously attached identity_document" do
      sign_in @urunis
      complete_step1
      get panel_onboarding_step2_url
      patch panel_onboarding_step2_url, params: {
        identity_verification_request: {
          identity_documents: [fixture_file_upload("id_placeholder.png", "image/png")]
        }
      }

      ivr = @urunis.reload.current_onboarding_request.identity_verification_request
      attachment = ivr.identity_documents.first
      assert attachment.present?

      assert_difference -> { ivr.identity_documents.count }, -1 do
        delete panel_onboarding_delete_document_url(attachment_id: attachment.id)
      end
    end

    # --- update_step3 — BR-019 toggle delegation vs manual + delete_residence_document ---

    test "update_step3 accepts manual_address with street_name (BR-019)" do
      sign_in @urunis
      complete_step2_with_attachment
      get panel_onboarding_step3_url

      patch panel_onboarding_step3_url, params: {
        commit_continue: "Continuar",
        residence_verification_request: {
          manual_address: "1",
          street_name: "Calle Falsa",
          number: "123"
        }
      }

      rvr = @urunis.reload.current_onboarding_request.residence_verification_request
      assert_not_nil rvr
      assert_equal "Calle Falsa", rvr.street_name
      assert_equal "123", rvr.number
    end

    test "update_step3 accepts neighborhood_delegation_id without street_name (BR-019)" do
      sign_in @urunis
      complete_step2_with_attachment
      get panel_onboarding_step3_url

      patch panel_onboarding_step3_url, params: {
        commit_continue: "Continuar",
        residence_verification_request: {
          neighborhood_delegation_id: @delegation.id,
          number: "42"
        }
      }

      rvr = @urunis.reload.current_onboarding_request.residence_verification_request
      assert_not_nil rvr
      assert_equal @delegation.id, rvr.neighborhood_delegation_id
    end

    test "delete_residence_document removes a previously attached residence_document" do
      sign_in @urunis
      complete_step2_with_attachment
      get panel_onboarding_step3_url
      patch panel_onboarding_step3_url, params: {
        residence_verification_request: {
          neighborhood_delegation_id: @delegation.id,
          number: "42",
          residence_documents: [fixture_file_upload("id_placeholder.png", "image/png")]
        }
      }

      rvr = @urunis.reload.current_onboarding_request.residence_verification_request
      attachment = rvr.residence_documents.first
      assert attachment.present?

      assert_difference -> { rvr.residence_documents.count }, -1 do
        delete panel_onboarding_delete_residence_document_url(attachment_id: attachment.id)
      end
    end

    # --- submit action — terms gate + session cleanup ---

    test "submit redirects back to step4 when terms_accepted is missing" do
      sign_in @urunis
      complete_full_flow_until_step4

      post panel_onboarding_submit_url
      assert_redirected_to panel_onboarding_step4_url
      assert_equal I18n.t("panel.onboarding.step4.terms_required"), flash[:alert]

      # OR should still be draft
      onboarding = @urunis.reload.current_onboarding_request
      assert onboarding.draft?
    end

    test "submit with terms_accepted transitions OR to pending and clears session" do
      sign_in @urunis
      complete_full_flow_until_step4

      post panel_onboarding_submit_url, params: {terms_accepted: "1"}
      assert_redirected_to panel_root_url

      # urunis no longer has a current_onboarding_request because it transitioned to pending
      # and current_onboarding_request scope only includes draft/pending — wait pending IS included
      onboarding = @urunis.reload.current_onboarding_request
      assert_not_nil onboarding
      assert onboarding.pending?
      assert_not_nil onboarding.terms_accepted_at
      assert_equal "pending", onboarding.identity_verification_request.status
      assert_equal "pending", onboarding.residence_verification_request.status
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

    def complete_step2_with_attachment
      complete_step1
      get panel_onboarding_step2_url
      patch panel_onboarding_step2_url, params: {
        commit_continue: "Continuar",
        identity_verification_request: {
          first_name: "Urunis",
          last_name: "Test",
          run: "12345678-5",
          phone: "+56912345678",
          identity_documents: [fixture_file_upload("id_placeholder.png", "image/png")]
        }
      }
    end

    def complete_full_flow_until_step4
      complete_step2_with_attachment
      get panel_onboarding_step3_url
      patch panel_onboarding_step3_url, params: {
        commit_continue: "Continuar",
        residence_verification_request: {
          neighborhood_delegation_id: @delegation.id,
          number: "42",
          residence_documents: [fixture_file_upload("id_placeholder.png", "image/png")]
        }
      }
      get panel_onboarding_step4_url
    end
  end
end
