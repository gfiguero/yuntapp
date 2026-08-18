require "application_system_test_case"

# UC-003 · Solicitud de certificado de residencia
#
# El socio aprobado pide un certificado para un residente de su hogar. Termina en
# `pending_payment`: sin pago confirmado no hay emisión (BR-002, regla crítica del
# flujo).
class ResidenceCertificateRequestTest < ApplicationSystemTestCase
  setup do
    @user = users(:selendis)
    @password = "purifytheenemy"
    @member = members(:selendis_member)
    @association = neighborhood_associations(:manios_de_buin)
    @pricing = certificate_pricings(:manios_current_pricing)
  end

  test "UC-003: el household_admin solicita un certificado y queda en pending_payment" do
    sign_in_through_ui(@user, @password)

    visit new_panel_residence_certificate_path

    # El precio que ve el socio es el que fijó la junta (BR-005: mínimo $1.000).
    assert_operator @pricing.price, :>=, 1000

    select @member.name, from: "residence_certificate_member_id"
    fill_in "residence_certificate_purpose", with: "trámite bancario"
    click_button "Guardar"

    assert_text I18n.t("panel.residence_certificates.flash.requested")

    certificate = ResidenceCertificate.order(:created_at).last

    # BR-002 / regla crítica: nace esperando el pago, nunca emitido.
    assert_equal "pending_payment", certificate.status
    assert_nil certificate.issued_at

    # BR-027: queda atado a member + household_unit + asociación.
    assert_equal @member, certificate.member
    assert_equal @association, certificate.neighborhood_association
    assert_not_nil certificate.household_unit

    # BR-149: el monto se congela al crear, con el precio vigente de la junta.
    assert_equal @pricing.price, certificate.amount
    assert_equal "trámite bancario", certificate.purpose
  end

  private

  def sign_in_through_ui(user, password)
    visit new_user_session_path
    fill_in "user[email]", with: user.email
    fill_in "user[password]", with: password
    click_button class: "btn-primary", match: :first
    assert_no_selector "input[name='user[password]']", wait: 10
  end
end
