class IssueCertificateJob < ApplicationJob
  queue_as :default

  retry_on StandardError, attempts: 3, wait: :polynomially_longer

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
