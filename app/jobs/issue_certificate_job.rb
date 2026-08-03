class IssueCertificateJob < ApplicationJob
  queue_as :default

  # BR-076/BR-148: tres intentos con backoff. Si los tres fallan, el certificado
  # queda en `paid` sin PDF — el socio pagó y no tiene documento, y BR-063
  # prohíbe la devolución. Antes el job se rendía en silencio y nadie se
  # enteraba; ahora el staff recibe el aviso para resolverlo a mano. La causa
  # típica es una junta sin RUT (BR-120), que el guard de solicitud/pago ya
  # previene, pero el aviso cubre cualquier otro fallo de emisión.
  retry_on StandardError, attempts: 3, wait: :polynomially_longer do |job, error|
    certificate_id = job.arguments.first
    Rails.logger.error(
      "IssueCertificateJob se rindió con el certificado ##{certificate_id}: #{error.class}: #{error.message}"
    )
    certificate = ResidenceCertificate.find_by(id: certificate_id)
    IssueCertificateJob.notify_staff_of_failure(certificate, error) if certificate
  end

  def self.notify_staff_of_failure(certificate, error)
    User.where(superadmin: true).find_each do |staff|
      next if staff.email.blank?
      CertificateIssuanceFailureMailer.staff_alert(staff, certificate, error.message).deliver_later
    end
  end

  def perform(certificate_id)
    certificate = ResidenceCertificate.find_by(id: certificate_id)
    return if certificate.nil?

    # Idempotente: ya emitido y con PDF adjunto, no hay nada que hacer.
    return if certificate.issued? && certificate.pdf_document.attached?

    # Emitimos desde `paid`; también reingresamos si quedó `issued` SIN PDF
    # (BR-076: si la generación del PDF falló tras issue!, el reintento debe
    # poder re-adjuntar el PDF faltante en vez de cortar por el guard de issued).
    return unless certificate.paid? || certificate.issued?

    certificate.issue! # idempotente: no-op si ya está issued (BR-062/BR-076)
    CertificatePdfService.new(certificate).generate_and_attach!
    ResidenceCertificateMailer.issued(certificate).deliver_later
  end
end
