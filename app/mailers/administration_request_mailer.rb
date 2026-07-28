class AdministrationRequestMailer < ApplicationMailer
  def submitted(administration_request)
    @request = administration_request
    return if @request.user.email.blank?
    mail to: @request.user.email, subject: t(".subject")
  end

  def approved(administration_request)
    @request = administration_request
    return if @request.user.email.blank?
    mail to: @request.user.email, subject: t(".subject")
  end

  def rejected(administration_request)
    @request = administration_request
    return if @request.user.email.blank?
    mail to: @request.user.email, subject: t(".subject")
  end

  # BR-130: aviso a un admin vigente de la junta objetivo.
  def notify_existing_admin(admin, administration_request)
    @request = administration_request
    @admin = admin
    return if admin.email.blank?
    mail to: admin.email, subject: t(".subject")
  end

  # BR-133: digest al staff con las solicitudes pendientes.
  def staff_digest(staff, requests)
    @requests = requests.to_a
    return if @requests.empty? || staff.email.blank?
    @staff = staff
    mail to: staff.email, subject: t(".subject", count: @requests.size)
  end
end
