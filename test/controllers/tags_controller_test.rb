require "test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @tag = tags(:one)
    @user = users(:artanis)
    sign_in @user
  end

  test "should get index" do
    get tags_url
    assert_response :success
  end

  test "should get search with json format" do
    get search_tags_url(format: :json), params: {items: [@tag.id]}
    assert_response :success

    json_response = JSON.parse(response.body)
    assert_not_empty json_response
    assert_equal @tag.id, json_response.first["value"]
  end

  test "should show tag" do
    get tag_url(@tag)
    assert_response :success
  end

  # BR-007, #115: este controller top-level es solo lectura (index/show/search).
  # Las rutas de escritura no deben existir.
  test "no write routes are exposed (BR-007, #115)" do
    assert_raises(StandardError) { new_tag_path }
    assert_raises(StandardError) { edit_tag_path(@tag) }
    assert_raises(StandardError) { delete_tag_path(@tag) }
  end
end
