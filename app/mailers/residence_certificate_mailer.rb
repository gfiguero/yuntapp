class ResidenceCertificateMailer < ApplicationMailer
  # Email enviado al usuario cuando un certificado de residencia se emite.
  # Para certificados de dependientes, el destinatario es el household_admin
  # que lo solicitó (Member#user returns requested_by para dependent members).
  def issued(certificate)
    @certificate = certificate
    @member = certificate.member
    @verification_url = build_verification_url(certificate.validation_token)
    recipient_email = certificate.member.user&.email
    return if recipient_email.blank?

    mail to: recipient_email
  end

  private

  def build_verification_url(token)
    base = Rails.application.config.x.verification_base_url.presence ||
      "https://#{ENV.fetch("YUNTAPP_HOST", "yuntapp.cl")}"
    "#{base.chomp("/")}/verify/#{token}"
  end
end
