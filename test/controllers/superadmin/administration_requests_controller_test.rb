require "test_helper"

module Superadmin
  class AdministrationRequestsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup { sign_in users(:artanis) }

    test "index lista solicitudes" do
      get superadmin_administration_requests_url
      assert_response :success
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

    test "un usuario no superadmin no accede" do
      sign_out users(:artanis)
      sign_in users(:selendis)
      get superadmin_administration_requests_url
      assert_redirected_to root_url
    end
  end
end
