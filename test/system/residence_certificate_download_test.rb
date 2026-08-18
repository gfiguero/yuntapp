require "application_system_test_case"

# UC-006 · Descarga del certificado
#
# Frontera deliberada: la descarga binaria en sí (`send_data`, headers, contenido
# del PDF) ya está cubierta en `test/controllers/panel/residence_certificates_controller_test.rb`,
# y verificarla aquí exigiría configurar el directorio de descargas de Chrome y
# esperar el archivo en disco — más flakiness que valor.
#
# Lo que este test cubre y ningún otro: que el socio *llega* al PDF. Navega desde
# el panel, encuentra su certificado en el listado, entra al detalle y el enlace
# de descarga está ahí, apuntando a la ruta correcta. Un certificado emitido que
# el socio no puede encontrar es un certificado que no existe.
class ResidenceCertificateDownloadTest < ApplicationSystemTestCase
  setup do
    @user = users(:selendis)
    @password = "purifytheenemy"
    @member = members(:selendis_member)

    @certificate = ResidenceCertificate.create!(
      member: @member,
      household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      purpose: "postulación a subsidio",
      status: "issued",
      folio: "CR-1-000077",
      validation_token: SecureRandom.uuid,
      validation_code: "D4WNL0AD",
      issue_date: Date.current,
      expiration_date: Date.current + 6.months, # BR-023
      issued_at: Time.current
    )
    @certificate.pdf_document.attach(
      io: StringIO.new("%PDF-1.4 contenido de prueba"),
      filename: "#{@certificate.folio}.pdf",
      content_type: "application/pdf"
    )
  end

  test "UC-006: el socio encuentra su certificado emitido y llega al enlace de descarga" do
    sign_in_through_ui

    visit panel_residence_certificates_path

    # El listado muestra folio y vigencia: lo que el socio necesita para
    # reconocer cuál de sus certificados sirve para el trámite que tiene entre manos.
    assert_text @certificate.folio
    assert_text I18n.t("activerecord.attributes.residence_certificate/status.issued")

    click_on @certificate.folio

    # El detalle trae los tres canales de validación del PDF.
    assert_text @certificate.validation_code
    assert_text "postulación a subsidio"

    assert_selector "a[href='#{download_panel_residence_certificate_path(@certificate)}']"
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
