require "test_helper"

module Panel
  class ResidenceCertificatesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @household_admin = users(:selendis)
      @non_admin = users(:karass)
      @member = members(:selendis_member)
      @residency = residencies(:selendis_residency)
      @association = neighborhood_associations(:manios_de_buin)
      @pricing = certificate_pricings(:manios_current_pricing)
    end

    # --- Authorization ---

    test "non household_admin is redirected" do
      sign_in @non_admin
      get panel_residence_certificates_url
      assert_redirected_to panel_root_url
    end

    test "unauthenticated is redirected" do
      get panel_residence_certificates_url
      assert_redirected_to new_user_session_url
    end

    test "household_admin can view index" do
      sign_in @household_admin
      get panel_residence_certificates_url
      assert_response :success
    end

    test "household_admin can view new with current pricing" do
      sign_in @household_admin
      get new_panel_residence_certificate_url
      assert_response :success
    end

    # BR-120/BR-148: una junta sin RUT no puede emitir, así que tampoco puede
    # aceptar solicitudes; el certificado quedaría pagado y atascado en `paid`
    # sin emisión posible y sin devolución (BR-063). El estado se fuerza con
    # update_column porque la columna es NOT NULL con validación de presencia
    # (BR-121): es un guard de defensa en profundidad, no un estado alcanzable
    # por la aplicación.
    test "no permite solicitar certificado si la junta no tiene RUT (BR-148)" do
      @association.update_column(:rut, "")
      sign_in @household_admin

      get new_panel_residence_certificate_url
      assert_redirected_to panel_residence_certificates_url

      assert_no_difference -> { ResidenceCertificate.count } do
        post panel_residence_certificates_url, params: {
          residence_certificate: {purpose: "trámite bancario", member_id: @residency.id}
        }
      end
      assert_redirected_to panel_residence_certificates_url
    end

    # --- Create ---

    test "create captures snapshot of current price as amount" do
      sign_in @household_admin

      assert_difference -> { ResidenceCertificate.count }, 1 do
        post panel_residence_certificates_url, params: {
          residence_certificate: {
            member_id: @residency.id,
            purpose: "trámite bancario"
          }
        }
      end

      cert = ResidenceCertificate.order(:created_at).last
      assert_equal @pricing.price, cert.amount
      assert_equal @pricing.price * 0.10, cert.platform_fee
      assert cert.pending_payment?
      assert_nil cert.payment_id
    end

    test "create snapshots the price at request time, even if price later changes" do
      sign_in @household_admin
      original_price = @pricing.price

      post panel_residence_certificates_url, params: {
        residence_certificate: {member_id: @residency.id, purpose: "test"}
      }
      cert = ResidenceCertificate.order(:created_at).last
      assert_equal original_price, cert.amount

      CertificatePricing.create!(
        neighborhood_association: @association,
        price: 5000,
        effective_from: Time.current,
        created_by: @household_admin
      )

      cert.reload
      assert_equal original_price, cert.amount, "amount snapshot must be immutable to pricing changes"
    end

    test "create fails when no current pricing defined" do
      sign_in @household_admin
      @pricing.destroy

      assert_no_difference -> { ResidenceCertificate.count } do
        post panel_residence_certificates_url, params: {
          residence_certificate: {member_id: @residency.id, purpose: "test"}
        }
      end

      assert_response :unprocessable_content
    end

    test "create ignores params attempts to set amount/payment_id/status" do
      sign_in @household_admin

      post panel_residence_certificates_url, params: {
        residence_certificate: {
          member_id: @residency.id,
          purpose: "test",
          amount: 99999,
          payment_id: "FAKE",
          status: "issued",
          platform_fee: 0
        }
      }

      cert = ResidenceCertificate.order(:created_at).last
      assert_equal @pricing.price, cert.amount
      assert_nil cert.payment_id
      assert cert.pending_payment?
    end

    # --- show with issued certificate ---

    test "show on issued cert displays download link and validation_code" do
      sign_in @household_admin

      cert = ResidenceCertificate.create!(
        member: @member,
        household_unit: household_units(:selendis_household),
        neighborhood_association: @association,
        purpose: "trámite bancario",
        status: "issued",
        folio: "CR-1-99",
        validation_token: "uuid-show-test",
        validation_code: "SHOWCODE",
        issue_date: Date.current,
        expiration_date: Date.current + 30.days,
        issued_at: Time.current
      )
      cert.pdf_document.attach(
        io: StringIO.new("%PDF-1.4 fake content"),
        filename: "test.pdf",
        content_type: "application/pdf"
      )

      get panel_residence_certificate_url(cert)
      assert_response :success
      assert_match I18n.t("panel.residence_certificates.show.download_pdf"), @response.body
      assert_match "SHOWCODE", @response.body
    end

    # --- BR-091/BR-092: bloqueo por desactivación y vencimiento ---

    test "deactivated member cannot request a new certificate" do
      sign_in @household_admin
      @member.deactivate!(reason: "ya no reside en el domicilio")

      get new_panel_residence_certificate_url
      assert_redirected_to panel_residence_certificates_url

      assert_no_difference -> { ResidenceCertificate.count } do
        post panel_residence_certificates_url, params: {
          residence_certificate: {member_id: @residency.id, purpose: "test"}
        }
      end
      assert_redirected_to panel_residence_certificates_url
    end

    # El PDF se envía por el controlador (send_data) en vez de redirigir al blob:
    # la URL de Active Storage no depende del usuario ni de downloadable? y con el
    # servicio Disk no expira, así que una URL guardada seguía sirviendo el
    # certificado tras vencer, ser desactivado el titular o revertirse el pago.
    test "download serves the stored PDF inline for a vigente certificate" do
      sign_in @household_admin
      cert = issued_cert
      attach_pdf(cert)

      get download_panel_residence_certificate_url(cert)
      assert_response :success
      assert_equal "application/pdf", @response.media_type
      assert_match(/attachment/, @response.headers["Content-Disposition"])
      assert_match(/#{cert.folio}\.pdf/, @response.headers["Content-Disposition"])
      assert_equal cert.pdf_document.download, @response.body
    end

    # BR-091/BR-092/BR-141: la autorización se revalúa en CADA descarga. Antes,
    # obtenida la URL del blob, seguía sirviendo el PDF indefinidamente.
    test "download stops serving the PDF once the certificate expires (BR-092)" do
      sign_in @household_admin
      cert = issued_cert
      attach_pdf(cert)

      get download_panel_residence_certificate_url(cert)
      assert_response :success

      cert.update_columns(expiration_date: Date.current - 1.day)

      get download_panel_residence_certificate_url(cert)
      assert_redirected_to panel_residence_certificate_url(cert)
      assert_equal I18n.t("panel.residence_certificates.flash.not_downloadable"), flash[:alert]
    end

    test "download is blocked for an expired certificate" do
      sign_in @household_admin
      cert = issued_cert(expiration: Date.current - 1.day)
      attach_pdf(cert)

      get download_panel_residence_certificate_url(cert)
      assert_redirected_to panel_residence_certificate_url(cert)
      assert_equal I18n.t("panel.residence_certificates.flash.not_downloadable"), flash[:alert]
    end

    test "download is blocked when the holder was deactivated" do
      sign_in @household_admin
      cert = issued_cert
      attach_pdf(cert)
      @member.deactivate!(reason: "fraude detectado")

      get download_panel_residence_certificate_url(cert)
      assert_redirected_to panel_residence_certificate_url(cert)
      assert_equal I18n.t("panel.residence_certificates.flash.not_downloadable"), flash[:alert]
    end

    test "show on expired cert shows notice instead of download link" do
      sign_in @household_admin
      cert = issued_cert(expiration: Date.current - 1.day)
      attach_pdf(cert)

      get panel_residence_certificate_url(cert)
      assert_response :success
      assert_match I18n.t("panel.residence_certificates.show.expired_notice"), @response.body
      assert_no_match I18n.t("panel.residence_certificates.show.download_pdf"), @response.body
    end

    test "show on cert of deactivated holder shows notice instead of download link" do
      sign_in @household_admin
      cert = issued_cert
      attach_pdf(cert)
      @member.deactivate!(reason: "fraude detectado")

      get panel_residence_certificate_url(cert)
      assert_response :success
      assert_match I18n.t("panel.residence_certificates.show.holder_deactivated_notice"), @response.body
      assert_no_match I18n.t("panel.residence_certificates.show.download_pdf"), @response.body
    end

    test "show on paid cert (awaiting issuance) shows processing message" do
      sign_in @household_admin

      cert = ResidenceCertificate.create!(
        member: @member,
        household_unit: household_units(:selendis_household),
        neighborhood_association: @association,
        purpose: "test",
        status: "paid",
        amount: 1500,
        payment_id: "MP-SHOW-PAID",
        paid_at: Time.current
      )

      get panel_residence_certificate_url(cert)
      assert_response :success
      assert_match I18n.t("panel.residence_certificates.show.processing"), @response.body
    end

    private

    # --- BR-041/BR-098: aislamiento entre núcleos familiares del mismo domicilio ---

    test "el selector no ofrece residentes de otro núcleo familiar del mismo domicilio" do
      vecino = residente_de_otro_nucleo

      sign_in @household_admin
      get new_panel_residence_certificate_url
      assert_response :success

      # El selector muestra el nombre del residente, no su RUN.
      assert_no_match vecino.name, @response.body,
        "BR-041: un residente de otro núcleo familiar no debe aparecer en el selector"
      assert_match @member.name, @response.body,
        "el residente del propio núcleo sí debe ofrecerse"
    end

    test "un POST manipulado no puede emitir a nombre de otro núcleo familiar" do
      vecino = residente_de_otro_nucleo
      residency_ajena = Residency.find_by(verified_identity: vecino)

      sign_in @household_admin

      assert_no_difference -> { ResidenceCertificate.count } do
        post panel_residence_certificates_url, params: {
          residence_certificate: {member_id: residency_ajena.id, purpose: "trámite bancario"}
        }
      end

      assert_response :unprocessable_content
    end

    # --- Trazabilidad de quién solicita (BR-152) ---

    test "create registra quién solicitó el certificado" do
      sign_in @household_admin

      assert_difference -> { ResidenceCertificate.count }, 1 do
        post panel_residence_certificates_url, params: {
          residence_certificate: {member_id: @residency.id, purpose: "trámite bancario"}
        }
      end

      certificate = ResidenceCertificate.order(:created_at).last
      assert_equal @household_admin, certificate.requested_by
    end

    # El caso que da sentido a la columna (BR-098): titular y solicitante son
    # personas distintas. Sin esto, el certificado de un dependiente no deja
    # rastro de quién lo pidió.
    test "el solicitante queda registrado aunque el titular sea un dependiente" do
      dependiente = dependiente_del_nucleo
      residency_dependiente = Residency.find_by(verified_identity: dependiente)

      sign_in @household_admin
      post panel_residence_certificates_url, params: {
        residence_certificate: {member_id: residency_dependiente.id, purpose: "matrícula escolar"}
      }

      certificate = ResidenceCertificate.order(:created_at).last
      assert_equal @household_admin, certificate.requested_by
      assert_not_equal certificate.member.verified_identity, @household_admin.verified_identity
    end

    # Residente dependiente del MISMO núcleo del solicitante (BR-065/BR-098).
    def dependiente_del_nucleo
      identidad = VerifiedIdentity.create!(
        first_name: "Rohana", last_name: "Khalai",
        run: "13579246-2", phone: "+56922223344"
      )
      Member.create!(verified_identity: identidad, neighborhood_association: @association,
        status: "approved", dependent: true, approved_at: Time.current)
      Residency.create!(
        verified_identity: identidad,
        verified_residence: @residency.verified_residence,
        household_unit: household_units(:selendis_household),
        family_group: @residency.family_group,
        household_admin: false,
        status: "approved"
      )
      identidad
    end

    # --- BR-041: aislamiento en LECTURA, no solo en emisión ---
    #
    # El PR #159 cerró la emisión (selectable_residencies y create) pero dejó
    # `index`, `show` y `download` scopeados por `household_unit`. El PDF que
    # sirve `download` lleva RUN sin enmascarar y domicilio completo, así que la
    # fuga era peor en lectura que en emisión.

    test "el índice no lista certificados de otro núcleo familiar del mismo domicilio" do
      ajeno = certificado_de_otro_nucleo

      sign_in @household_admin
      get panel_residence_certificates_url

      assert_response :success
      assert_no_match ajeno.folio, @response.body,
        "BR-041: el certificado de otra familia no debe aparecer en el índice"
    end

    test "show no expone el certificado de otro núcleo familiar" do
      ajeno = certificado_de_otro_nucleo

      sign_in @household_admin
      get panel_residence_certificate_url(ajeno)

      assert_response :not_found
    end

    test "download no entrega el PDF de otro núcleo familiar" do
      ajeno = certificado_de_otro_nucleo

      sign_in @household_admin
      get download_panel_residence_certificate_url(ajeno)

      assert_response :not_found
    end

    test "el propio núcleo sigue viendo y descargando sus certificados" do
      propio = issued_cert
      attach_pdf(propio)

      sign_in @household_admin
      get panel_residence_certificates_url
      assert_match propio.folio, @response.body

      get panel_residence_certificate_url(propio)
      assert_response :success

      get download_panel_residence_certificate_url(propio)
      assert_response :success
      assert_equal "application/pdf", @response.media_type
    end

    # Certificado emitido a nombre del household_admin de OTRO núcleo familiar
    # que comparte la misma dirección física.
    def certificado_de_otro_nucleo
      vecino = residente_de_otro_nucleo
      member = Member.find_by(verified_identity: vecino)

      cert = ResidenceCertificate.create!(
        member: member,
        household_unit: household_units(:selendis_household),
        neighborhood_association: @association,
        purpose: "certificado de la otra familia",
        status: "issued",
        folio: "CR-2026-9999-00042",
        folio_year: 2026,
        folio_sequence: 42,
        validation_token: SecureRandom.uuid,
        validation_code: SecureRandom.alphanumeric(8).upcase,
        issue_date: Date.current,
        expiration_date: Date.current + 30.days,
        issued_at: Time.current
      )
      cert.pdf_document.attach(
        io: StringIO.new("%PDF-1.4 contenido ajeno"),
        filename: "ajeno.pdf",
        content_type: "application/pdf"
      )
      cert
    end

    # Segundo núcleo familiar en la MISMA dirección física (BR-040): otra familia
    # que convive, con su propio household_admin y su Member aprobado en la junta.
    def residente_de_otro_nucleo
      household = household_units(:selendis_household)
      otro_grupo = FamilyGroup.create!(household_unit: household)

      identidad = VerifiedIdentity.create!(
        first_name: "Zeratul", last_name: "Nerazim",
        run: "9876543-3", phone: "+56911112233", email: "zeratul@shakuras.io"
      )
      Member.create!(verified_identity: identidad, neighborhood_association: @association,
        status: "approved", approved_at: Time.current)
      Residency.create!(
        verified_identity: identidad,
        verified_residence: @residency.verified_residence,
        household_unit: household,
        family_group: otro_grupo,
        household_admin: true,
        status: "approved"
      )

      identidad
    end

    def issued_cert(expiration: Date.current + 30.days)
      ResidenceCertificate.create!(
        member: @member,
        household_unit: household_units(:selendis_household),
        neighborhood_association: @association,
        purpose: "trámite bancario",
        status: "issued",
        folio: "CR-1-#{rand(1_000_000)}",
        validation_token: SecureRandom.uuid,
        validation_code: SecureRandom.alphanumeric(8).upcase,
        issue_date: Date.current,
        expiration_date: expiration,
        issued_at: Time.current
      )
    end

    def attach_pdf(cert)
      cert.pdf_document.attach(
        io: StringIO.new("%PDF-1.4 fake content"),
        filename: "test.pdf",
        content_type: "application/pdf"
      )
    end
  end
end
