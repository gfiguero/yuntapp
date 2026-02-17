module Panel
  class AccountResetsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!

    def destroy
      verified_identity = current_user.verified_identity

      if verified_identity
        verified_identity.members.each(&:destroy)
        current_user.update!(verified_identity: nil, admin: false, neighborhood_association: nil)
        verified_identity.destroy
      else
        current_user.update!(admin: false, neighborhood_association: nil)
      end

      session.delete(:onboarding)

      redirect_to panel_root_path, notice: I18n.t("panel.account_resets.flash.completed")
    end
  end
end
