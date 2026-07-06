class OnboardingReminderMailer < ApplicationMailer
  # BR-050: recordatorio-resumen al admin mientras su junta tenga solicitudes
  # de onboarding en estado `pending` sin revisar. Un solo correo por admin
  # agrupa todas las pendientes de su junta (sin spam por solicitud).
  def pending_digest(admin, requests)
    @requests = requests.to_a
    return if @requests.empty?
    return if admin.email.blank?

    @admin = admin
    @count = @requests.size
    @panel_url = build_panel_url

    mail to: admin.email, subject: t(".subject", count: @count)
  end

  private

  def build_panel_url
    base = Rails.application.config.x.verification_base_url.presence ||
      "https://#{ENV.fetch("YUNTAPP_HOST", "yuntapp.cl")}"
    "#{base.chomp("/")}/admin/onboarding_requests"
  end
end
