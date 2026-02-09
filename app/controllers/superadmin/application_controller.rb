module Superadmin
  class ApplicationController < ::ApplicationController
    layout "superadmin"
    before_action :authenticate_user!
    before_action :ensure_superadmin!

    private

    def ensure_superadmin!
      unless current_user.superadmin?
        redirect_to root_path, alert: "Acceso denegado. Se requieren permisos de superadministrador."
      end
    end
  end
end
