require "application_system_test_case"

# UC-008 · Onboarding de administración de junta (pasos 1-6, los del dirigente)
#
# Igual que en UC-002, el test cubre el tramo del actor: hasta que la solicitud
# queda `pending` en la bandeja del staff. La revisión y aprobación (pasos 7-9)
# es del superadmin y vive en otro flujo.
#
# El motivo de que esto sea un system test y no un controller test: los tres
# selects de región/comuna/junta se renderizan **vacíos** (`form.select :region_id, []`)
# y los puebla el `administration_cascade_controller` de Stimulus desde un JSON
# embebido. Sin navegador no hay opciones que elegir, así que un controller test
# solo puede simular el POST final — nunca el camino que recorre el dirigente.
class AdministrationRequestTest < ApplicationSystemTestCase
  setup do
    # Cuenta confirmada, no admin de ninguna junta (BR-136) y sin solicitud activa.
    # Ojo: `karass` no sirve aquí — tiene una AdministrationRequest pending en
    # fixtures y el guard `redirect_if_active_request` desvía el formulario.
    @user = users(:rohana)
    @password = "keeperoftradition"
    @association = neighborhood_associations(:association_0)
    @commune = @association.commune
    @region = @commune.region
    @document = Rails.root.join("test/fixtures/files/id_placeholder.png")
  end

  test "UC-008: un dirigente solicita administrar su junta y queda pending para el staff" do
    sign_in_through_ui

    visit new_panel_administration_request_path

    # Los selects los puebla Stimulus en cascada; sin JS estarían vacíos.
    select @region.name, from: "administration_request_region_id"
    select @commune.name, from: "administration_request_commune_id"
    select @association.name, from: "administration_request_neighborhood_association_id"

    fill_in "administration_request_organization_rut", with: "76543210-3"
    select I18n.t("admin.board_members.positions.presidente", default: "Presidente"),
      from: "administration_request_position"

    fill_in "administration_request_first_name", with: "Rohana"
    fill_in "administration_request_last_name", with: "Nerazim"
    fill_in "administration_request_run", with: "15432198-5"
    fill_in "administration_request_phone", with: "987654321"

    attach_file "administration_request_directiva_validity_document", @document
    attach_file "administration_request_identity_documents", @document

    click_button I18n.t("panel.administration_requests.submit")

    # Turbo envía el form por fetch: hay que esperar a que la navegación ocurra
    # antes de mirar la base, o se lee de una transacción que todavía no cerró.
    assert_text I18n.t("panel.administration_requests.flash.submitted"), wait: 10

    request = AdministrationRequest.where(user: @user).sole

    # Postcondición del tramo del dirigente: la solicitud llega al staff.
    assert_equal "pending", request.status
    assert_equal @association, request.neighborhood_association
    assert_equal "presidente", request.position

    # BR-010 / BR-013: RUN y teléfono quedan normalizados por los callbacks.
    assert_equal "15432198-5", request.run
    assert_equal "+56987654321", request.phone
    assert_equal "76543210-3", request.organization_rut

    # Los documentos que el staff necesita para verificar (paso 8).
    assert request.directiva_validity_document.attached?
    assert request.identity_documents.attached?

    # El usuario todavía NO es admin: eso solo ocurre al aprobar (paso 9).
    assert_not @user.reload.admin?
    assert_nil @user.neighborhood_association_id
  end

  private

  def sign_in_through_ui
    visit new_user_session_path
    fill_in "user[email]", with: @user.email
    fill_in "user[password]", with: @password
    click_button class: "btn-primary", match: :first
    assert_no_selector "input[name='user[password]']", wait: 10
  end
end
