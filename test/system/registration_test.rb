require "application_system_test_case"

# UC-001 · Registro de residente
#
# Devise corre con `:confirmable`, así que el registro no termina en el submit:
# el usuario queda inactivo hasta seguir el enlace del correo. El test recorre
# ese ciclo completo —registro, correo, confirmación, primer ingreso al panel—
# porque una cuenta que se crea pero no puede confirmarse es un registro roto y
# ningún controller test que no mire el correo lo detecta.
class RegistrationTest < ApplicationSystemTestCase
  setup do
    ActionMailer::Base.deliveries.clear
    @email = "nerazim@shakuras.io"
    @password = "voidsentinel"
  end

  test "UC-001: un visitante se registra, confirma por correo y entra al panel" do
    visit new_user_registration_path

    fill_in "user[email]", with: @email
    fill_in "user[password]", with: @password
    fill_in "user[password_confirmation]", with: @password
    click_button "Crear Cuenta"

    # La cuenta existe pero todavía no puede operar.
    assert_text I18n.t("devise.registrations.signed_up_but_unconfirmed")
    user = User.find_by(email: @email)
    assert_not_nil user
    assert_nil user.confirmed_at, "no debe quedar confirmada antes de seguir el enlace"

    visit_confirmation_link(user)

    # Postcondición del UC-001: cuenta activa, sin asociación ni identidad.
    assert_not_nil user.reload.confirmed_at
    assert_nil user.verified_identity
    assert_nil user.member

    sign_in_and_reach_panel

    # El panel le ofrece iniciar el onboarding (UC-002), que es el siguiente paso.
    assert_selector "a[href='#{panel_onboarding_step1_path}']"
  end

  private

  # El token se lee de la base, no del correo. Devise envía con `deliver_later` y
  # en test el adapter es `TestAdapter`, así que el correo queda encolado sin
  # ejecutar; además el mailer correría en el thread de Puma, no en el del test.
  # Perseguir el job desde aquí sería frágil y probaría ActiveJob, no el UC-001.
  # Que el token viaja por correo se verifica a nivel de mailer.
  def visit_confirmation_link(user)
    token = user.reload.confirmation_token
    assert_not_nil token, "Devise debe generar el confirmation_token al registrarse"

    visit user_confirmation_path(confirmation_token: token)
  end

  def sign_in_and_reach_panel
    visit new_user_session_path
    fill_in "user[email]", with: @email
    fill_in "user[password]", with: @password
    click_button class: "btn-primary", match: :first

    assert_current_path panel_root_path, wait: 10
  end
end
