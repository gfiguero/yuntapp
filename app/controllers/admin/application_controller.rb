module Admin
  class ApplicationController < ::ApplicationController
    layout "admin"
    before_action :authenticate_user!
    before_action :ensure_admin!

    private

    def ensure_admin!
      unless current_user.admin?
        redirect_to root_path, alert: "Acceso denegado. Se requieren permisos de administrador."
      end
    end
  end
end
