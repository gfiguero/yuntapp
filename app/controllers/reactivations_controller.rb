# Reactivación auto-servicio de cuentas desactivadas (BR-100, forma A: por correo).
# Público: el usuario no puede iniciar sesión mientras está desactivado.
class ReactivationsController < ApplicationController
  layout "auth"
  skip_before_action :authenticate_user!

  # GET /account/reactivate
  def new
  end

  # POST /account/reactivate
  # Envía el enlace solo si la cuenta está auto-desactivada (no bloqueada por admin).
  # Responde siempre igual para no revelar qué correos existen.
  def create
    email = params[:email].to_s.strip.downcase
    user = User.find_by(email: email)
    ReactivationMailer.instructions(user).deliver_later if user&.deactivated? && !user.blocked?

    redirect_to new_user_session_path, notice: I18n.t("reactivations.flash.sent")
  end

  # GET /account/reactivate/:token
  def show
    @user = User.find_by_token_for(:account_reactivation, params[:token])
    return if @user&.deactivated? && !@user.blocked?

    redirect_to new_user_session_path, alert: I18n.t("reactivations.flash.invalid")
  end

  # PATCH /account/reactivate/:token
  def update
    user = User.find_by_token_for(:account_reactivation, params[:token])

    if user&.deactivated? && !user.blocked?
      user.reactivate!
      redirect_to new_user_session_path, notice: I18n.t("reactivations.flash.reactivated")
    else
      redirect_to new_user_session_path, alert: I18n.t("reactivations.flash.invalid")
    end
  end
end
