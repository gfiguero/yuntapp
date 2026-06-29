require "test_helper"

module Users
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "sign-up creates an unconfirmed user and sends a confirmation email" do
      assert_emails 1 do
        assert_difference -> { User.count }, 1 do
          post user_registration_url, params: {
            user: {
              email: "newuser@yuntapp.test",
              password: "secret-password-123",
              password_confirmation: "secret-password-123"
            }
          }
        end
      end

      user = User.find_by(email: "newuser@yuntapp.test")
      assert_not_nil user
      assert_nil user.confirmed_at
      assert_not_nil user.confirmation_token
      assert_not_nil user.confirmation_sent_at
    end

    test "sign-up redirects with a notice about pending confirmation" do
      post user_registration_url, params: {
        user: {
          email: "another@yuntapp.test",
          password: "secret-password-123",
          password_confirmation: "secret-password-123"
        }
      }

      assert_redirected_to root_url
      follow_redirect!
      # Devise default message includes the word "confirmation" or its translation
      assert_match(/confirma/i, flash[:notice].to_s)
    end
  end
end
