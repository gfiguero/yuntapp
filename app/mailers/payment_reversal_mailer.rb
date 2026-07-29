class PaymentReversalMailer < ApplicationMailer
  # BR-141: aviso al staff (superadmin) de que un pago fue revertido
  # (refund/contracargo). El payable es un ResidenceCertificate o Listing.
  def staff_alert(staff, payable)
    return if staff.email.blank?
    @payable = payable
    @kind = payable.is_a?(ResidenceCertificate) ? :certificate : :listing
    mail to: staff.email, subject: t(".subject")
  end
end
