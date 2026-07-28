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

  test "should show neighborhood_association" do
    get neighborhood_association_url(@neighborhood_association)
    assert_response :success
  end

  # BR-100: las juntas no se destruyen; no existe ruta destroy en este controller.
  test "there is no destroy route for neighborhood associations" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        "/neighborhood_associations/#{@neighborhood_association.id}",
        method: :delete
      )
    end
  end

  # BR-007, #115: este controller top-level es solo lectura (index/show/search).
  # Las rutas de escritura no deben existir.
  test "no write routes are exposed (BR-007, #115)" do
    assert_raises(StandardError) { new_neighborhood_association_path }
    assert_raises(StandardError) { edit_neighborhood_association_path(@neighborhood_association) }
  end
end
