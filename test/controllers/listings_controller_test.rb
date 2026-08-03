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

  # BR-083: la vitrina pública solo muestra publicaciones con la habilitación
  # pagada. Antes consultaba Listing.all, y como toda publicación nace en
  # pending_payment, cualquiera publicaba gratis.
  test "index only lists paid publications (BR-083)" do
    unpaid = listings(:artanis_warp_prism)
    assert unpaid.pending_payment?, "la fixture debe estar impaga"

    get listings_url(format: :json)
    assert_response :success

    ids = JSON.parse(response.body).map { |listing| listing["id"] }
    assert_includes ids, @listing.id
    assert_not_includes ids, unpaid.id
  end

  test "show returns 404 for an unpaid publication (BR-083)" do
    unpaid = listings(:artanis_warp_prism)

    get listing_url(unpaid)
    assert_response :not_found
  end

  test "search does not leak unpaid publications (BR-083)" do
    unpaid = listings(:artanis_warp_prism)

    get search_listings_url(format: :json), params: {items: [unpaid.id]}
    assert_response :success
    assert_empty JSON.parse(response.body)
  end

  # BR-086: la vigencia son 30 días desde el pago; al vencer sale de la vitrina.
  test "index excludes expired publications (BR-086)" do
    @listing.update_columns(published_until: 1.day.ago.to_date)

    get listings_url(format: :json)
    assert_response :success
    assert_not_includes JSON.parse(response.body).map { |l| l["id"] }, @listing.id
  end

  # BR-100: una publicación retirada (active: false) conserva su registro pero
  # deja de mostrarse.
  test "index excludes withdrawn publications (BR-100)" do
    @listing.withdraw!

    get listings_url(format: :json)
    assert_response :success
    assert_not_includes JSON.parse(response.body).map { |l| l["id"] }, @listing.id
  end

  test "items=all bypass does not leak unpaid publications (BR-083)" do
    get listings_url(format: :json), params: {items: "all"}
    assert_response :success

    ids = JSON.parse(response.body).map { |listing| listing["id"] }
    assert_equal [@listing.id], ids
  end
end
