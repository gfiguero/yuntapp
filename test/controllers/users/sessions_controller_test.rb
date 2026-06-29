require "test_helper"

module Users
  class SessionsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "user with confirmed email can sign in" do
      user = users(:karass)
      assert_not_nil user.confirmed_at

      post user_session_url, params: {
        user: {email: user.email, password: "honorandduty"}
      }

      assert_redirected_to panel_root_url
    end

    test "user without confirmed email cannot sign in" do
      user = users(:karass)
      user.update_columns(confirmed_at: nil, confirmation_token: "pending-token", confirmation_sent_at: Time.current)

      post user_session_url, params: {
        user: {email: user.email, password: "honorandduty"}
      }

      # Devise redirects back to the sign-in form with an alert
      assert_redirected_to new_user_session_url
      assert_match(/confirma/i, flash[:alert].to_s)
    end

    test "user can confirm email via valid token and then sign in" do
      raw_token, encoded_token = Devise.token_generator.generate(User, :confirmation_token)
      user = User.new(email: "tobeconfirmed@yuntapp.test", password: "secret-password-123")
      user.confirmation_token = encoded_token
      user.confirmation_sent_at = Time.current
      user.save!(validate: false)

      get user_confirmation_url(confirmation_token: raw_token)
      assert_redirected_to new_user_session_url

      user.reload
      assert_not_nil user.confirmed_at

      post user_session_url, params: {
        user: {email: user.email, password: "secret-password-123"}
      }
      assert_redirected_to panel_root_url
    end
  end
end
