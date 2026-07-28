module Panel
  # Auto-desactivación de la propia cuenta (BR-100). No borra nada: desactiva la cuenta
  # y su historial en cascada. El usuario puede reactivarla luego vía su correo (forma A).
  class AccountDeactivationsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!

    # GET /panel/account_deactivation/new
    def new
    end

    # POST /panel/account_deactivation
    def create
      current_user.deactivate!
      sign_out(current_user)
      redirect_to new_user_session_path, notice: I18n.t("panel.account_deactivations.flash.deactivated")
    end
  end
end
