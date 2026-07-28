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

  test "should show listing" do
    get listing_url(@listing)
    assert_response :success
  end

  # BR-007, #115: este controller top-level es solo lectura (index/show/search).
  # Las rutas de escritura no deben existir.
  test "no write routes are exposed (BR-007, #115)" do
    assert_raises(StandardError) { new_listing_path }
    assert_raises(StandardError) { edit_listing_path(@listing) }
    assert_raises(StandardError) { delete_listing_path(@listing) }
  end
end
