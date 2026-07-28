require "test_helper"

class ReactivationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:karax)
  end

  test "new renders the request form" do
    get new_reactivation_url
    assert_response :success
  end

  test "create sends a reactivation email for a deactivated account" do
    @user.deactivate!

    assert_enqueued_emails 1 do
      post reactivations_url, params: {email: @user.email}
    end
    assert_redirected_to new_user_session_url
  end

  test "create does not send email for an active account" do
    assert_no_enqueued_emails do
      post reactivations_url, params: {email: @user.email}
    end
    assert_redirected_to new_user_session_url
  end

  test "create does not send email for a blocked account" do
    @user.deactivate!
    @user.block!(by: users(:artanis), reason: "x")

    assert_no_enqueued_emails do
      post reactivations_url, params: {email: @user.email}
    end
  end

  test "show with a valid token renders the confirmation" do
    @user.deactivate!
    token = @user.generate_token_for(:account_reactivation)

    get reactivate_account_url(token: token)
    assert_response :success
  end

  test "show with an invalid token redirects" do
    get reactivate_account_url(token: "garbage")
    assert_redirected_to new_user_session_url
  end

  test "update with a valid token reactivates the account" do
    @user.deactivate!
    token = @user.generate_token_for(:account_reactivation)

    patch reactivate_account_url(token: token)

    assert_redirected_to new_user_session_url
    assert_not @user.reload.deactivated?
  end

  test "update refuses to reactivate a blocked account" do
    @user.deactivate!
    token = @user.generate_token_for(:account_reactivation)
    @user.block!(by: users(:artanis), reason: "x")

    patch reactivate_account_url(token: token)

    assert @user.reload.deactivated?, "sigue desactivada (bloqueada)"
  end
end
