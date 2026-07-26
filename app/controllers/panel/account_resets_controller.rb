module Panel
  class AccountResetsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!

    # BR-030: restablecer la cuenta NO destruye datos. Se desactivan las membresías
    # activas (deactivate! → inactive, con cascada a dependientes) y se desvincula la
    # cuenta; la identidad verificada, residencias y certificados emitidos se conservan
    # como historial auditable. El usuario puede volver a hacer onboarding.
    def destroy
      verified_identity = current_user.verified_identity

      if verified_identity
        verified_identity.members.active.find_each do |member|
          member.deactivate!(reason: I18n.t("panel.account_resets.deactivation_reason"))
        end
        current_user.update!(verified_identity: nil, admin: false, neighborhood_association: nil)
      else
        current_user.update!(admin: false, neighborhood_association: nil)
      end

      session.delete(:onboarding)

      redirect_to panel_root_path, notice: I18n.t("panel.account_resets.flash.completed")
    end
  end
end
