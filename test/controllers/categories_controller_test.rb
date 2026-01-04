require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @category = categories(:one)
    @user = users(:artanis)
    sign_in @user
  end

  test "should get index" do
    get categories_url
    assert_response :success
  end

  test "should get search with json format" do
    get search_categories_url(format: :json), params: { items: [@category.id] }
    assert_response :success
    
    json_response = JSON.parse(response.body)
    assert_not_empty json_response
    assert_equal @category.id, json_response.first["value"]
  end

  test "should get new" do
    get new_category_url
    assert_response :success
  end

  test "should create category" do
    assert_difference("Category.count") do
      post categories_url, params: { category: { name: "New Category" } }
    end

    assert_redirected_to category_url(Category.last)
  end

  test "should not create category with invalid params" do
    assert_no_difference("Category.count") do
      post categories_url, params: { category: { name: "" } }
    end

    assert_response :unprocessable_content
  end

  test "should show category" do
    get category_url(@category)
    assert_response :success
  end

  test "should get edit" do
    get edit_category_url(@category)
    assert_response :success
  end

  test "should update category" do
    patch category_url(@category), params: { category: { name: "Updated Category" } }
    assert_redirected_to category_url(@category)
    @category.reload
    assert_equal "Updated Category", @category.name
  end

  test "should not update category with invalid params" do
    patch category_url(@category), params: { category: { name: "" } }
    assert_response :unprocessable_content
  end

  test "should get delete" do
    get delete_category_url(@category)
    assert_response :success
  end

  test "should destroy category" do
    assert_difference("Category.count", -1) do
      delete category_url(@category)
    end

    assert_redirected_to categories_url
  end
end
