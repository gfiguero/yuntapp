require "application_system_test_case"

# UC-007 · Verificación pública del certificado
#
# El único flujo de la app sin login: un banco, arrendador u organismo entra a
# /verify, teclea el código alfanumérico del PDF y obtiene la confirmación.
#
# Las variantes (vencido, anulado, inexistente, rate limiting) están cubiertas en
# `test/controllers/verifications_controller_test.rb`, que es donde corresponden:
# aquí solo se verifica que el flujo funciona de punta a punta en un navegador.
class CertificateVerificationTest < ApplicationSystemTestCase
  setup do
    # `verify` está detrás de Rack::Attack; sin esto el test hereda el contador
    # de otros tests y empieza a recibir 429.
    Rack::Attack.cache.store.clear

    @member = members(:selendis_member)
    @certificate = ResidenceCertificate.create!(
      member: @member,
      household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      purpose: "trámite bancario",
      status: "issued",
      folio: "CR-1-000042",
      validation_token: SecureRandom.uuid,
      validation_code: "X7K9M2P4",
      issue_date: Date.current,
      expiration_date: Date.current + 6.months, # BR-023
      issued_at: Time.current
    )
  end

  test "UC-007: cualquiera verifica un certificado por su código, sin login" do
    visit verify_path
    assert_text "Verificar certificado"

    fill_in "identifier", with: @certificate.validation_code
    click_button "Verificar"

    assert_text "Certificado válido"
    assert_text "Vigente"

    # Los datos que el verificador necesita para confiar en el documento.
    assert_text @certificate.folio
    assert_text @member.name
    assert_text "trámite bancario"
    assert_text neighborhood_associations(:manios_de_buin).name

    # El RUN va parcialmente oculto: el verificador confirma identidad sin que la
    # página exponga el RUN completo a cualquiera que tenga el código.
    assert_text "1.XXX.XXX-1"
    assert_no_text "11111111-1"
  end

  test "UC-007: el mismo certificado se verifica por la URL del QR" do
    visit verification_path(identifier: @certificate.validation_token)

    assert_text "Certificado válido"
    assert_text @certificate.folio
  end
end
