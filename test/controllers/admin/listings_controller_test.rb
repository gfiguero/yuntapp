require "test_helper"

module Admin
  class ListingsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @listing = listings(:artanis_zealot_gauntlets)
      @user = users(:artanis)
      sign_in @user
    end

    test "should get index" do
      get admin_listings_url
      assert_response :success
    end

    test "should get search with json format" do
      get search_admin_listings_url(format: :json), params: {items: [@listing.id]}
      assert_response :success

      json_response = JSON.parse(response.body)
      assert_not_empty json_response
      assert_equal @listing.id, json_response.first["value"]
    end

    test "should get new" do
      get new_admin_listing_url
      assert_response :success
    end

    test "should create listing" do
      assert_difference("Listing.count") do
        post admin_listings_url, params: {listing: {
          active: @listing.active,
          description: @listing.description,
          name: "New Admin Listing",
          price: @listing.price,
          user_id: @user.id
        }}
      end

      assert_redirected_to admin_listing_url(Listing.last)
    end

    test "should not create listing with invalid params" do
      assert_no_difference("Listing.count") do
        post admin_listings_url, params: {listing: {name: ""}}
      end

      assert_response :unprocessable_content
    end

    test "should show listing" do
      get admin_listing_url(@listing)
      assert_response :success
    end

    test "should get edit" do
      get edit_admin_listing_url(@listing)
      assert_response :success
    end

    test "should update listing" do
      patch admin_listing_url(@listing), params: {listing: {name: "Updated Admin Listing"}}
      assert_redirected_to admin_listing_url(@listing)
      @listing.reload
      assert_equal "Updated Admin Listing", @listing.name
    end

    test "should not update listing with invalid params" do
      patch admin_listing_url(@listing), params: {listing: {name: ""}}
      assert_response :unprocessable_content
    end

    test "should get delete" do
      get delete_admin_listing_url(@listing)
      assert_response :success
    end

    test "should destroy listing" do
      assert_difference("Listing.count", -1) do
        delete admin_listing_url(@listing)
      end

      assert_redirected_to admin_listings_url
    end
  end
end
