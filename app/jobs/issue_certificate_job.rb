class IssueCertificateJob < ApplicationJob
  queue_as :default

  retry_on StandardError, attempts: 3, wait: :polynomially_longer

  def perform(certificate_id)
    certificate = ResidenceCertificate.find_by(id: certificate_id)
    return if certificate.nil?
    return if certificate.issued?
    return unless certificate.paid?

    certificate.issue!
    CertificatePdfService.new(certificate).generate_and_attach!
    ResidenceCertificateMailer.issued(certificate).deliver_later
  end
end
