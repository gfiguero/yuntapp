require "test_helper"

module Panel
  class NeighborhoodAssociationControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @member_user = users(:selendis)
      @non_member = users(:karass)
      @association = neighborhood_associations(:manios_de_buin)
    end

    test "redirects when user is not signed in" do
      get panel_neighborhood_association_url
      assert_redirected_to new_user_session_url
    end

    test "redirects when user has no active member" do
      sign_in @non_member
      get panel_neighborhood_association_url
      assert_redirected_to panel_root_url
    end

    test "member can view their association info" do
      sign_in @member_user
      get panel_neighborhood_association_url
      assert_response :success
      assert_match @association.name, response.body
    end
  end
end
