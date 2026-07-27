require "test_helper"

module Panel
  class AccountDeactivationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = users(:selendis)
    end

    test "new renders the confirmation" do
      sign_in @user
      get new_panel_account_deactivation_url
      assert_response :success
    end

    test "create deactivates the account and signs out, without destroying it" do
      sign_in @user
      member = members(:selendis_member)

      assert_no_difference("User.count") do
        post panel_account_deactivation_url
      end

      assert_redirected_to new_user_session_url
      assert @user.reload.deactivated?
      assert member.reload.inactive?, "cascada: la membresía queda inactive"
    end

    test "requires authentication" do
      post panel_account_deactivation_url
      assert_redirected_to new_user_session_url
    end
  end
end
