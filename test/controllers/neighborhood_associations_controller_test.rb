require "test_helper"

class NeighborhoodAssociationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @neighborhood_association = neighborhood_associations(:manios_de_buin)
    @user = users(:artanis)
    sign_in @user
  end

  test "should get index" do
    get neighborhood_associations_url
    assert_response :success
  end

  test "should get search with json format" do
    get search_neighborhood_associations_url(format: :json), params: {items: [@neighborhood_association.id]}
    assert_response :success

    json_response = JSON.parse(response.body)
    assert_not_empty json_response
    assert_equal @neighborhood_association.id, json_response.first["value"]
  end

  test "should get new" do
    get new_neighborhood_association_url
    assert_response :success
  end

  test "should create neighborhood_association" do
    assert_difference("NeighborhoodAssociation.count") do
      post neighborhood_associations_url, params: {neighborhood_association: {name: "New NeighborhoodAssociation"}}
    end

    assert_redirected_to neighborhood_association_url(NeighborhoodAssociation.last)
  end

  test "should not create neighborhood_association with invalid params" do
    assert_no_difference("NeighborhoodAssociation.count") do
      post neighborhood_associations_url, params: {neighborhood_association: {name: ""}}
    end

    assert_response :unprocessable_content
  end

  test "should show neighborhood_association" do
    get neighborhood_association_url(@neighborhood_association)
    assert_response :success
  end

  test "should get edit" do
    get edit_neighborhood_association_url(@neighborhood_association)
    assert_response :success
  end

  test "should update neighborhood_association" do
    patch neighborhood_association_url(@neighborhood_association), params: {neighborhood_association: {name: "Updated NeighborhoodAssociation"}}
    assert_redirected_to neighborhood_association_url(@neighborhood_association)
    @neighborhood_association.reload
    assert_equal "Updated NeighborhoodAssociation", @neighborhood_association.name
  end

  test "should not update neighborhood_association with invalid params" do
    patch neighborhood_association_url(@neighborhood_association), params: {neighborhood_association: {name: ""}}
    assert_response :unprocessable_content
  end

  test "should get delete" do
    get delete_neighborhood_association_url(@neighborhood_association)
    assert_response :success
  end

  test "should destroy neighborhood_association" do
    assert_difference("NeighborhoodAssociation.count", -1) do
      delete neighborhood_association_url(@neighborhood_association)
    end

    assert_redirected_to neighborhood_associations_url
  end
end
