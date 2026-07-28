require "test_helper"

module Admin
  # BR-007: la acción search de los controllers admin no debe filtrar registros de
  # otras juntas. Se prueba sobre members como representante del patrón (#95).
  class MembersSearchScopeTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @admin = users(:selendis) # admin de manios_de_buin
      @own_member = members(:selendis_member)
      sign_in @admin
    end

    test "search returns a member of the admin's own association" do
      get search_admin_members_url(format: :json), params: {items: [@own_member.id]}
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal @own_member.id, json.first["value"]
    end

    test "search does not leak a member from another association" do
      identity = VerifiedIdentity.create!(first_name: "Ajeno", last_name: "Otro", run: "66666666-6", phone: "+56911112222", email: "ajeno@example.com")
      foreign_member = Member.create!(verified_identity: identity, neighborhood_association: neighborhood_associations(:association_0), status: "approved")

      get search_admin_members_url(format: :json), params: {items: [foreign_member.id]}
      assert_response :success
      assert_empty JSON.parse(response.body)
    end
  end
end
