class ReactivationMailer < ApplicationMailer
  # Envía el enlace de reactivación al correo de la cuenta desactivada.
  # BR-100: solo cuentas auto-desactivadas (no bloqueadas por admin) reciben el enlace.
  def instructions(user)
    @user = user
    @token = user.generate_token_for(:account_reactivation)
    @url = reactivate_account_url(token: @token)
    mail(to: user.email, subject: I18n.t("reactivation_mailer.instructions.subject"))
  end
end
