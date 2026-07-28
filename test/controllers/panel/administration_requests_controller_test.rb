require "test_helper"

module Panel
  class AdministrationRequestsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "new muestra el formulario para un usuario no admin" do
      sign_in users(:urunis)
      get new_panel_administration_request_url
      assert_response :success
      assert_select "select[name='administration_request[neighborhood_association_id]']"
    end

    test "un admin existente no puede solicitar (BR-136)" do
      sign_in users(:selendis) # admin: true
      get new_panel_administration_request_url
      assert_redirected_to panel_root_url
    end

    test "create con datos validos crea la solicitud en pending" do
      sign_in users(:urunis)
      assert_difference "AdministrationRequest.count", 1 do
        post panel_administration_request_url, params: {administration_request: {
          neighborhood_association_id: neighborhood_associations(:manios_de_buin).id,
          organization_rut: neighborhood_associations(:manios_de_buin).rut,
          position: "presidente",
          first_name: "Ana", last_name: "Soto", run: "15111222-6", phone: "987654321"
        }}
      end
      assert_equal "pending", AdministrationRequest.last.status
      assert_redirected_to panel_administration_request_url
    end
  end
end
