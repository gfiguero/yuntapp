require "application_system_test_case"

# UC-002 · Onboarding: convertirse en socio
#
# Piloto de la estrategia "un system test por caso de uso". Recorre el flujo
# completo de 4 pasos en un navegador real porque es la única forma de cubrir lo
# que aquí vive en el cliente y ningún test de controller alcanza:
#
#   - los selects en cascada Región → Comuna → Junta, que se repueblan por Turbo
#     Stream (`onchange: this.form.requestSubmit()`), no por un submit de página;
#   - el `autosave_controller` de Stimulus, que guarda cada campo por separado
#     con 2s de debounce en vez de un POST único al final;
#   - los botones "Continuar", que arrancan `disabled` y solo se habilitan cuando
#     el servidor confirma que el paso quedó completo;
#   - el `terms_acceptance_controller`, que habilita el envío final (BR-015).
#
# La postcondición que se verifica es BR-017: el envío es atómico, las tres
# solicitudes pasan a `pending` juntas.
class OnboardingTest < ApplicationSystemTestCase
  setup do
    @user = users(:urunis) # sin onboarding previo ni member
    @password = "bladeofjustice"
    @association = neighborhood_associations(:association_0)
    @commune = @association.commune
    @region = @commune.region
    @delegation = neighborhood_delegations(:neighborhood_delegation_0_0)
    @document = Rails.root.join("test/fixtures/files/id_placeholder.png")
  end

  test "UC-002: un usuario registrado completa los 4 pasos y su solicitud queda pending" do
    sign_in_through_ui

    complete_step1_association
    complete_step2_identity
    complete_step3_residence
    submit_step4_review

    # Postcondición del UC-002: la solicitud llega al admin.
    onboarding_request = @user.onboarding_requests.sole
    assert_equal "pending", onboarding_request.status
    assert_equal @association, onboarding_request.neighborhood_association
    assert_not_nil onboarding_request.terms_accepted_at, "BR-015: debe registrar la aceptación de términos"

    # BR-017: el envío es atómico — las tres pasan a pending juntas.
    assert_equal "pending", onboarding_request.identity_verification_request.status
    assert_equal "pending", onboarding_request.residence_verification_request.status

    # Los datos tecleados llegaron completos, no solo el estado.
    identity = onboarding_request.identity_verification_request
    assert_equal "Nerazim", identity.first_name
    assert_equal "Vorazun", identity.last_name
    assert_equal "15432198-5", identity.run
    assert_equal "+56987654321", identity.phone, "BR-013: el teléfono se normaliza a +569XXXXXXXX"
    assert identity.identity_documents.attached?

    residence = onboarding_request.residence_verification_request
    assert_equal @delegation.id, residence.neighborhood_delegation_id
    assert_equal "1234", residence.number
  end

  private

  def sign_in_through_ui
    visit new_user_session_path
    fill_in "user[email]", with: @user.email
    fill_in "user[password]", with: @password
    click_button class: "btn-primary", match: :first
    assert_no_selector "input[name='user[password]']", wait: 10
  end

  # Paso 1 — selects en cascada por Turbo Stream. Cada `select` dispara un PATCH
  # que repuebla el siguiente, que hasta entonces está `disabled`.
  def complete_step1_association
    visit panel_onboarding_step1_path
    assert_text "Selecciona tu Junta de Vecinos"

    select @region.name, from: "region_id"
    assert_selector "select[name='commune_id']:not([disabled])", wait: 10

    select @commune.name, from: "commune_id"
    assert_selector "select[name='neighborhood_association_id']:not([disabled])", wait: 10

    select @association.name, from: "neighborhood_association_id"
    continue_when_enabled
  end

  # Paso 2 — autosave por campo con 2s de debounce. El botón se habilita solo
  # cuando el servidor confirmó los cuatro campos y el documento adjunto.
  def complete_step2_identity
    assert_text "Verifica tu Identidad"

    fill_in "identity_verification_request_first_name", with: "Nerazim"
    fill_in "identity_verification_request_last_name", with: "Vorazun"
    fill_in "identity_verification_request_run", with: "15432198-5"
    fill_in "identity_verification_request_phone", with: "987654321"
    attach_file "identity_verification_request_identity_documents", @document

    continue_when_enabled
  end

  # Paso 3 — delegación vecinal (BR-019: delegación O calle manual) + número
  # obligatorio (BR-020).
  def complete_step3_residence
    assert_text "Define tu Domicilio"

    select @delegation.name, from: "residence_verification_request_neighborhood_delegation_id"
    fill_in "residence_verification_request_number", with: "1234"

    continue_when_enabled
  end

  # Paso 4 — el envío está bloqueado hasta aceptar los términos (BR-015).
  def submit_step4_review
    assert_text "Revisa y Confirma"
    assert_text @association.name
    assert_text "15432198-5"

    assert_selector "button[type='submit'][disabled]", text: "Enviar Solicitud"
    check "terms_accepted"
    click_button "Enviar Solicitud"

    assert_text I18n.t("panel.onboarding.flash.completed"), wait: 10
  end

  # El botón "Continuar" arranca `disabled` y lo habilita el turbo_stream que
  # llega cuando el autosave confirma el paso. Esperar a que se habilite es la
  # señal fiable de que el servidor guardó — no un sleep fijo.
  def continue_when_enabled
    assert_selector "input[name='commit_continue']:not([disabled])", wait: 15
    find("input[name='commit_continue']").click
  end
end
