require "test_helper"

module Superadmin
  class NeighborhoodAssociationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @neighborhood_association = neighborhood_associations(:manios_de_buin)
      @user = users(:artanis)
      sign_in @user
    end

    test "should get index" do
      get superadmin_neighborhood_associations_url
      assert_response :success
    end

    test "should get search with json format" do
      get search_superadmin_neighborhood_associations_url(format: :json), params: {items: [@neighborhood_association.id]}
      assert_response :success

      json_response = JSON.parse(response.body)
      assert_not_empty json_response
      assert_equal @neighborhood_association.id, json_response.first["value"]
    end

    test "should get new" do
      get new_superadmin_neighborhood_association_url
      assert_response :success
    end

    test "should create neighborhood_association" do
      assert_difference("NeighborhoodAssociation.count") do
        post superadmin_neighborhood_associations_url, params: {neighborhood_association: {name: "New NeighborhoodAssociation", rut: valid_test_rut(2)}}
      end

      assert_redirected_to superadmin_neighborhood_association_url(NeighborhoodAssociation.last)
    end

    test "should not create neighborhood_association with invalid params" do
      assert_no_difference("NeighborhoodAssociation.count") do
        post superadmin_neighborhood_associations_url, params: {neighborhood_association: {name: ""}}
      end

      assert_response :unprocessable_content
    end

    test "should show neighborhood_association" do
      get superadmin_neighborhood_association_url(@neighborhood_association)
      assert_response :success
    end

    test "should get edit" do
      get edit_superadmin_neighborhood_association_url(@neighborhood_association)
      assert_response :success
    end

    test "should update neighborhood_association" do
      patch superadmin_neighborhood_association_url(@neighborhood_association), params: {neighborhood_association: {name: "Updated NeighborhoodAssociation"}}
      assert_redirected_to superadmin_neighborhood_association_url(@neighborhood_association)
      @neighborhood_association.reload
      assert_equal "Updated NeighborhoodAssociation", @neighborhood_association.name
    end

    test "should not update neighborhood_association with invalid params" do
      patch superadmin_neighborhood_association_url(@neighborhood_association), params: {neighborhood_association: {name: ""}}
      assert_response :unprocessable_content
    end

    test "should get deactivate" do
      get deactivate_superadmin_neighborhood_association_url(@neighborhood_association)
      assert_response :success
    end

    # BR-054/BR-055/BR-100: disolver marca inactive y cascadea Members; NO destruye.
    test "confirm_deactivate marks the association inactive without destroying it" do
      member = members(:selendis_member)
      assert member.approved?

      assert_no_difference("NeighborhoodAssociation.count") do
        patch confirm_deactivate_superadmin_neighborhood_association_url(@neighborhood_association)
      end

      assert_redirected_to superadmin_neighborhood_association_url(@neighborhood_association)
      assert_not @neighborhood_association.reload.active?, "la junta debe quedar inactive"
      assert member.reload.inactive?, "sus socios activos pasan a inactive (BR-054)"
    end

    test "there is no destroy route for neighborhood associations" do
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path(
          "/superadmin/neighborhood_associations/#{@neighborhood_association.id}",
          method: :delete
        )
      end
    end
  end
end
