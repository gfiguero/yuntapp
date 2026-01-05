require "test_helper"

class ListingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @listing = listings(:artanis_zealot_gauntlets)
    @user = users(:artanis)
    sign_in @user
  end

  test "should get index" do
    get listings_url
    assert_response :success
  end

  test "should get search with json format" do
    get search_listings_url(format: :json), params: {items: [@listing.id]}
    assert_response :success

    json_response = JSON.parse(response.body)
    assert_not_empty json_response
    assert_equal @listing.id, json_response.first["value"]
  end

  test "should get new" do
    get new_listing_url
    assert_response :success
  end

  test "should create listing" do
    assert_difference("Listing.count") do
      post listings_url, params: {listing: {
        active: @listing.active,
        description: @listing.description,
        name: "New Unique Listing",
        price: @listing.price,
        user_id: @user.id
      }}
    end

    assert_redirected_to listing_url(Listing.last)
  end

  test "should not create listing with invalid params" do
    assert_no_difference("Listing.count") do
      post listings_url, params: {listing: {name: ""}} # Name is required assuming validation
    end

    assert_response :unprocessable_content
  end

  test "should show listing" do
    get listing_url(@listing)
    assert_response :success
  end

  test "should get edit" do
    get edit_listing_url(@listing)
    assert_response :success
  end

  test "should update listing" do
    patch listing_url(@listing), params: {listing: {name: "Updated Name"}}
    assert_redirected_to listing_url(@listing)
    @listing.reload
    assert_equal "Updated Name", @listing.name
  end

  test "should not update listing with invalid params" do
    patch listing_url(@listing), params: {listing: {name: ""}}
    assert_response :unprocessable_content
  end

  test "should get delete" do
    get delete_listing_url(@listing)
    assert_response :success
  end

  test "should destroy listing" do
    assert_difference("Listing.count", -1) do
      delete listing_url(@listing)
    end

    assert_redirected_to listings_url
  end
end
