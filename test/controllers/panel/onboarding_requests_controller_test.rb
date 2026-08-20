require "test_helper"

module Panel
  # BR-047 (historial visible) y BR-048/BR-049 (duplicar para corregir).
  class OnboardingRequestsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = users(:karass)
      @other_user = users(:karax)
      @request_record = onboarding_requests(:karass_pending)
      @request_record.update!(status: "rejected", rejection_reason: "Documento ilegible")
    end

    # --- Authorization ---

    test "redirects when user is not signed in" do
      get panel_onboarding_history_url
      assert_redirected_to new_user_session_url
    end

    test "duplicate redirects when user is not signed in" do
      post panel_onboarding_request_duplicate_url(@request_record)
      assert_redirected_to new_user_session_url
    end

    # --- Index (BR-047) ---

    test "index lists the user's own requests with the rejection reason" do
      sign_in @user
      get panel_onboarding_history_url

      assert_response :success
      assert_match "Documento ilegible", response.body
    end

    test "index does not leak another user's requests" do
      other = onboarding_requests(:karax_pending)
      other.update!(status: "rejected", rejection_reason: "Motivo ajeno del vecino karax")

      sign_in @user
      get panel_onboarding_history_url

      assert_response :success
      assert_no_match "Motivo ajeno del vecino karax", response.body
    end

    # --- Duplicate (BR-048/BR-049) ---

    test "duplicate creates a draft copy and sends the user back to the wizard" do
      sign_in @user

      assert_difference "OnboardingRequest.count", 1 do
        post panel_onboarding_request_duplicate_url(@request_record)
      end

      copy = @user.onboarding_requests.order(:created_at).last
      assert_equal "draft", copy.status
      assert_redirected_to panel_onboarding_step1_url
    end

    test "duplicate leaves the original untouched" do
      sign_in @user
      post panel_onboarding_request_duplicate_url(@request_record)

      @request_record.reload
      assert_equal "rejected", @request_record.status
      assert_equal "Documento ilegible", @request_record.rejection_reason
    end

    # Aislamiento: el id viaja por la URL, así que un POST manipulado no debe
    # alcanzar la solicitud de otro usuario.
    test "duplicate cannot reach another user's request" do
      other = onboarding_requests(:karax_pending)
      other.update!(status: "rejected", rejection_reason: "Ajeno")

      sign_in @user
      assert_no_difference "OnboardingRequest.count" do
        post panel_onboarding_request_duplicate_url(other)
      end
      assert_response :not_found
    end

    test "duplicate refuses a request that is not rejected or cancelled" do
      @request_record.update_columns(status: "approved")

      sign_in @user
      assert_no_difference "OnboardingRequest.count" do
        post panel_onboarding_request_duplicate_url(@request_record)
      end
      assert_redirected_to panel_onboarding_history_url
    end

    # Un usuario con solicitud activa no puede abrir una segunda: el wizard
    # trabaja sobre `current_onboarding_request`, que asume una sola.
    test "duplicate refuses when the user already has an active request" do
      OnboardingRequest.create!(user: @user, status: "draft")

      sign_in @user
      assert_no_difference "OnboardingRequest.count" do
        post panel_onboarding_request_duplicate_url(@request_record)
      end
      assert_redirected_to panel_onboarding_history_url
    end
  end
end
