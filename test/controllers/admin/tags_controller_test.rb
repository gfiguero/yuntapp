require "test_helper"

module Admin
  class TagsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @tag = tags(:one)
      @user = users(:artanis)
      sign_in @user
    end

    test "should get index" do
      get admin_tags_url
      assert_response :success
    end

    test "should get search with json format" do
      get search_admin_tags_url(format: :json), params: {items: [@tag.id]}
      assert_response :success

      json_response = JSON.parse(response.body)
      assert_not_empty json_response
      assert_equal @tag.id, json_response.first["value"]
    end

    test "should get new" do
      get new_admin_tag_url
      assert_response :success
    end

    test "should create tag" do
      assert_difference("Tag.count") do
        post admin_tags_url, params: {tag: {name: "New Admin Tag"}}
      end

      assert_redirected_to admin_tag_url(Tag.last)
    end

    test "should not create tag with invalid params" do
      assert_no_difference("Tag.count") do
        post admin_tags_url, params: {tag: {name: ""}}
      end

      assert_response :unprocessable_content
    end

    test "should show tag" do
      get admin_tag_url(@tag)
      assert_response :success
    end

    test "should get edit" do
      get edit_admin_tag_url(@tag)
      assert_response :success
    end

    test "should update tag" do
      patch admin_tag_url(@tag), params: {tag: {name: "Updated Admin Tag"}}
      assert_redirected_to admin_tag_url(@tag)
      @tag.reload
      assert_equal "Updated Admin Tag", @tag.name
    end

    test "should not update tag with invalid params" do
      patch admin_tag_url(@tag), params: {tag: {name: ""}}
      assert_response :unprocessable_content
    end

    test "should get delete" do
      get delete_admin_tag_url(@tag)
      assert_response :success
    end

    test "should destroy tag" do
      assert_difference("Tag.count", -1) do
        delete admin_tag_url(@tag)
      end

      assert_redirected_to admin_tags_url
    end
  end
end
