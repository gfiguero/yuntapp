require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @category = categories(:weapons)
    @user = users(:artanis)
    sign_in @user
  end

  test "should get index" do
    get categories_url
    assert_response :success
  end

  test "should get search with json format" do
    get search_categories_url(format: :json), params: {items: [@category.id]}
    assert_response :success

    json_response = JSON.parse(response.body)
    assert_not_empty json_response
    assert_equal @category.id, json_response.first["value"]
  end

  test "should show category" do
    get category_url(@category)
    assert_response :success
  end

  # BR-007, #115: este controller top-level es solo lectura (index/show/search).
  # Las rutas de escritura no deben existir.
  test "no write routes are exposed (BR-007, #115)" do
    assert_raises(StandardError) { new_category_path }
    assert_raises(StandardError) { edit_category_path(@category) }
    assert_raises(StandardError) { delete_category_path(@category) }
  end
end
