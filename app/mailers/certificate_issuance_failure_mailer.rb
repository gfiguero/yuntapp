class CertificateIssuanceFailureMailer < ApplicationMailer
  # BR-148: aviso al staff (superadmin) de que un certificado pagado agotó los
  # reintentos de emisión y quedó atascado en `paid`. Requiere intervención
  # manual: el socio pagó y BR-063 prohíbe la devolución.
  def staff_alert(staff, certificate, error_message)
    return if staff.email.blank?
    @certificate = certificate
    @error_message = error_message
    mail to: staff.email, subject: t(".subject")
  end
end
