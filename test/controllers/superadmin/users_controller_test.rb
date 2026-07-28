require "test_helper"

module Superadmin
  class UsersControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @superadmin = users(:artanis)
      @user = users(:karax)
      sign_in @superadmin
    end

    test "should get block confirmation" do
      get block_superadmin_user_url(@user)
      assert_response :success
    end

    test "confirm_block blocks the account without destroying it" do
      assert_no_difference("User.count") do
        patch confirm_block_superadmin_user_url(@user), params: {block_reason: "Fraude"}
      end
      assert_redirected_to superadmin_user_url(@user)
      assert @user.reload.blocked?
      assert_equal @superadmin, @user.blocked_by
    end

    test "cannot block a superadmin" do
      other_super = User.create!(email: "other_super@example.com", password: "password123", confirmed_at: Time.current, superadmin: true)

      patch confirm_block_superadmin_user_url(other_super), params: {block_reason: "x"}

      assert_not other_super.reload.blocked?
    end

    test "unblock restores the account" do
      @user.block!(by: @superadmin, reason: "x")

      patch unblock_superadmin_user_url(@user)

      assert_redirected_to superadmin_user_url(@user)
      assert_not @user.reload.blocked?
    end

    test "there is no destroy route for users" do
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/superadmin/users/#{@user.id}", method: :delete)
      end
    end
  end
end
