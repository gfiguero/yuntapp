require "test_helper"

class IssueCertificateJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @certificate = ResidenceCertificate.create!(
      member: members(:selendis_member),
      household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-JOB-TEST",
      paid_at: Time.current
    )
  end

  test "perform issues the certificate and attaches a PDF" do
    IssueCertificateJob.new.perform(@certificate.id)

    @certificate.reload
    assert @certificate.issued?
    assert @certificate.folio.present?
    assert @certificate.validation_token.present?
    assert @certificate.validation_code.present?
    assert @certificate.pdf_document.attached?
  end

  test "perform enqueues the issued notification email" do
    assert_enqueued_emails 1 do
      IssueCertificateJob.new.perform(@certificate.id)
    end
  end

  test "perform is a full no-op when already issued with a PDF attached" do
    @certificate.update!(
      status: "issued",
      folio: "CR-1-100",
      validation_token: "preset-token",
      validation_code: "PRESET12"
    )
    @certificate.pdf_document.attach(
      io: StringIO.new("%PDF-1.4 fake"),
      filename: "cert.pdf",
      content_type: "application/pdf"
    )

    assert_no_enqueued_emails do
      IssueCertificateJob.new.perform(@certificate.id)
    end

    @certificate.reload
    assert_equal "preset-token", @certificate.validation_token
    assert_equal "PRESET12", @certificate.validation_code
  end

  test "perform backfills the PDF when certificate is issued without one (BR-076 retry)" do
    # Simula un certificado ya emitido (issue! corrió) al que solo le faltó
    # adjuntar el PDF porque la generación falló en el intento anterior.
    @certificate.update!(
      status: "issued",
      folio: "CR-1-100",
      validation_token: "preset-token",
      validation_code: "PRESET12",
      issue_date: Date.current,
      expiration_date: Date.current + 30.days,
      issued_at: Time.current
    )
    assert_not @certificate.pdf_document.attached?

    IssueCertificateJob.new.perform(@certificate.id)

    @certificate.reload
    # No re-emite: conserva folio/token/code (issue! es idempotente)
    assert_equal "preset-token", @certificate.validation_token
    assert_equal "PRESET12", @certificate.validation_code
    # Pero sí adjunta el PDF que había faltado
    assert @certificate.pdf_document.attached?
  end

  test "perform is a no-op when certificate is not paid" do
    @certificate.update_columns(status: "pending_payment")

    IssueCertificateJob.new.perform(@certificate.id)

    @certificate.reload
    assert @certificate.pending_payment?
  end

  test "perform handles missing certificate gracefully" do
    assert_nothing_raised do
      IssueCertificateJob.new.perform(999999)
    end
  end

  # BR-148: si la emisión agota los reintentos, el certificado queda en `paid`
  # sin PDF — el socio pagó y no tiene documento, y BR-063 prohíbe la
  # devolución. Antes el job se rendía en silencio; ahora avisa al staff.
  test "notify_staff_of_failure encola un aviso para cada superadmin (BR-148)" do
    superadmins = User.where(superadmin: true).where.not(email: [nil, ""])
    assert superadmins.any?, "el fixture debe tener al menos un superadmin"

    assert_enqueued_emails superadmins.count do
      IssueCertificateJob.notify_staff_of_failure(@certificate, RuntimeError.new("junta sin RUT"))
    end
  end

  test "el job avisa al staff cuando agota los reintentos (BR-148)" do
    # Junta sin RUT: `issue!` aborta en todos los intentos (BR-120).
    neighborhood_associations(:manios_de_buin).update_column(:rut, "")

    staff_count = User.where(superadmin: true).where.not(email: [nil, ""]).count

    # `retry_on` con bloque no re-lanza al agotar los intentos: el bloque es
    # quien gestiona la rendición, y ahí es donde avisamos al staff.
    assert_emails staff_count do
      perform_enqueued_jobs { IssueCertificateJob.perform_later(@certificate.id) }
    end

    assert @certificate.reload.paid?, "el certificado queda en paid para revisión manual"
    assert_not @certificate.pdf_document.attached?
  end
end
