require "test_helper"

module Superadmin
  class AdministrationRequestsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup { sign_in users(:artanis) }

    test "index lista solicitudes" do
      get superadmin_administration_requests_url
      assert_response :success
    end

    # --- Advertencias al staff antes de aprobar (BR-137/139/140) ---

    def upload
      Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/id_placeholder.png"), "image/png")
    end

    # BR-140: el cargo ya tiene titular activo y la aprobación no lo desplaza,
    # así que la junta quedaría con dos presidentes. El staff debe saberlo.
    test "show advierte que el cargo ya está ocupado (BR-140)" do
      req = administration_requests(:pending_manios) # presidente de manios
      assert BoardMember.active.exists?(
        neighborhood_association: neighborhood_associations(:manios_de_buin), position: "presidente"
      )

      get superadmin_administration_request_url(req)

      assert_response :success
      assert_match I18n.t("superadmin.administration_requests.warn_position_taken",
        position: I18n.t("admin.board_members.positions.presidente"),
        name: members(:selendis_member).name), @response.body
    end

    # BR-137: aprobar desactiva al solicitante como socio en sus otras juntas e
    # invalida los certificados que tenga allí. La cascada ya se ejecutaba; la
    # advertencia previa es lo que faltaba.
    test "show advierte que se desactivará la membresía en otra junta (BR-137)" do
      identidad = verified_identities(:selendis_persona)
      otra = neighborhood_associations(:association_0)
      req = AdministrationRequest.create!(
        user: users(:urunis),
        neighborhood_association: otra,
        organization_rut: otra.rut,
        position: "tesorero",
        first_name: identidad.first_name, last_name: identidad.last_name,
        run: identidad.run, phone: "+56911114444",
        status: "pending", directiva_validity_document: upload
      )

      get superadmin_administration_request_url(req)

      assert_response :success
      assert_match neighborhood_associations(:manios_de_buin).name, @response.body
      assert_match I18n.t("superadmin.administration_requests.warn_deactivates_memberships",
        associations: neighborhood_associations(:manios_de_buin).name), @response.body
    end

    # BR-139: junta nueva con nombre+comuna igual a una existente. Advertencia,
    # no bloqueo: decide el staff.
    test "show advierte posible junta duplicada (BR-139)" do
      existente = neighborhood_associations(:manios_de_buin)
      req = AdministrationRequest.create!(
        user: users(:urunis),
        proposed_association_name: existente.name,
        commune: existente.commune,
        organization_rut: "86429665-3",
        position: "director",
        first_name: "Ana", last_name: "Soto", run: "15111222-6", phone: "+56911112222",
        status: "pending", directiva_validity_document: upload
      )

      get superadmin_administration_request_url(req)

      assert_response :success
      assert_match I18n.t("superadmin.administration_requests.warn_duplicate_association",
        name: existente.name, commune: existente.commune.name), @response.body
    end

    test "show no advierte nada cuando no hay conflictos" do
      req = AdministrationRequest.create!(
        user: users(:urunis),
        proposed_association_name: "Junta Sin Conflictos",
        commune: communes(:commune_0_0_1),
        organization_rut: "86429665-3",
        position: "director",
        first_name: "Ana", last_name: "Soto", run: "15111222-6", phone: "+56911112222",
        status: "pending", directiva_validity_document: upload
      )

      get superadmin_administration_request_url(req)

      assert_response :success
      assert_no_match(/Verifica que no sea un duplicado/, @response.body)
      assert_no_match(/quedará desactivado como socio/, @response.body)
      assert_no_match(/ya lo ocupa/, @response.body)
    end

    test "approve aprueba y crea admin" do
      req = administration_requests(:pending_manios)
      patch approve_superadmin_administration_request_url(req)
      assert req.reload.approved?
      assert req.user.reload.admin?
    end

    test "reject exige motivo y marca rejected" do
      req = administration_requests(:pending_manios)
      patch reject_superadmin_administration_request_url(req), params: {administration_request: {rejection_reason: "Documentación insuficiente"}}
      assert req.reload.rejected?
      assert_equal "Documentación insuficiente", req.rejection_reason
    end

    test "reject sin motivo no cambia el estado" do
      req = administration_requests(:pending_manios)
      patch reject_superadmin_administration_request_url(req), params: {administration_request: {rejection_reason: ""}}
      assert req.reload.pending?
    end

    test "no se puede aprobar dos veces (no duplica BoardMember)" do
      req = administration_requests(:pending_manios)
      patch approve_superadmin_administration_request_url(req)
      assert req.reload.approved?
      assert_no_difference "BoardMember.count" do
        patch approve_superadmin_administration_request_url(req)
      end
    end

    test "no se puede rechazar un request ya aprobado" do
      req = administration_requests(:pending_manios)
      patch approve_superadmin_administration_request_url(req)
      patch reject_superadmin_administration_request_url(req), params: {administration_request: {rejection_reason: "tarde"}}
      assert req.reload.approved? # sigue approved, no rejected
    end

    test "approve exige confirmacion si el RUN ya está verificado en otra identidad (I3)" do
      req = administration_requests(:pending_manios)
      # identidad ajena con el mismo RUN (no ligada al solicitante)
      VerifiedIdentity.create!(first_name: "Otra", last_name: "Persona", run: req.run)

      patch approve_superadmin_administration_request_url(req)
      assert req.reload.pending?, "no debe aprobar sin confirmación"
      assert_not req.user.reload.admin?

      patch approve_superadmin_administration_request_url(req), params: {confirm_duplicate_run: "1"}
      assert req.reload.approved?, "debe aprobar con confirmación"
    end

    test "un usuario no superadmin no accede" do
      sign_out users(:artanis)
      sign_in users(:selendis)
      get superadmin_administration_requests_url
      assert_redirected_to root_url
    end
  end
end
