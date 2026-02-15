module Panel
  class AccountResetsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!

    def destroy
      persona = current_user.persona

      if persona
        persona.members.each(&:destroy)
        current_user.update!(persona: nil, admin: false, neighborhood_association: nil)
        persona.destroy
      else
        current_user.update!(admin: false, neighborhood_association: nil)
      end

      session.delete(:onboarding)

      redirect_to panel_root_path, notice: I18n.t("account_reset.message.completed")
    end
  end
end
