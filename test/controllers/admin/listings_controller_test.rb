require "test_helper"

module Admin
  class ListingsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @admin = users(:selendis) # admin de manios_de_buin
      # Publicación de un usuario de la junta del admin (aislamiento multi-tenant).
      @listing = Listing.create!(user: @admin, name: "Silla de la junta", active: true)
      sign_in @admin
    end

    test "should get index" do
      get admin_listings_url
      assert_response :success
    end

    test "should get search scoped to the admin's association" do
      get search_admin_listings_url(format: :json), params: {items: [@listing.id]}
      assert_response :success

      json_response = JSON.parse(response.body)
      assert_not_empty json_response
      assert_equal @listing.id, json_response.first["value"]
    end

    # BR-007: el search no expone publicaciones de otra junta.
    test "search does not leak listings from another association" do
      foreign = Listing.create!(user: users(:artanis), name: "Ajena", active: true)

      get search_admin_listings_url(format: :json), params: {items: [foreign.id]}
      assert_response :success

      json_response = JSON.parse(response.body)
      assert_empty json_response
    end

    test "should show listing" do
      get admin_listing_url(@listing)
      assert_response :success
    end

    # BR-007: no se puede ver una publicación de otra junta (IDOR).
    test "cannot show a listing from another association" do
      foreign = Listing.create!(user: users(:artanis), name: "Ajena", active: true)
      get admin_listing_url(foreign)
      assert_response :not_found
    end

    test "should get edit" do
      get edit_admin_listing_url(@listing)
      assert_response :success
    end

    test "should update listing" do
      patch admin_listing_url(@listing), params: {listing: {name: "Silla actualizada"}}
      assert_redirected_to admin_listing_url(@listing)
      assert_equal "Silla actualizada", @listing.reload.name
    end

    # BR-007: user_id no es asignable (no se puede reasignar el dueño).
    test "update ignores user_id" do
      original_user_id = @listing.user_id
      patch admin_listing_url(@listing), params: {listing: {name: "X", user_id: users(:artanis).id}}
      assert_equal original_user_id, @listing.reload.user_id
    end

    test "there is no create route for admin listings" do
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/admin/listings", method: :post)
      end
    end
  end
end
