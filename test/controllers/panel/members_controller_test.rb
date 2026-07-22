require "test_helper"

module Panel
  class MembersControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @household_admin = users(:selendis)
      @non_admin = users(:karass)
    end

    # --- Authorization ---

    test "redirects when user is not household_admin" do
      sign_in @non_admin
      get panel_members_url
      assert_redirected_to panel_root_url
    end

    test "redirects when user is not signed in" do
      get panel_members_url
      assert_redirected_to new_user_session_url
    end

    # --- Index ---

    test "household_admin can view index with other residencies listed" do
      sign_in @household_admin
      get panel_members_url
      assert_response :success
      # vorazun comparte el domicilio de selendis y debe listarse;
      # la propia residency de selendis queda excluida.
      assert_match verified_identities(:vorazun_persona).name, response.body
      assert_no_match verified_identities(:selendis_persona).name, response.body
    end
  end
end
