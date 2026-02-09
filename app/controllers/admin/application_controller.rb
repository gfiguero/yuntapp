module Admin
  class ApplicationController < ::ApplicationController
    layout "admin"
    before_action :authenticate_user!
    before_action :ensure_neighborhood_admin!

    private

    def ensure_neighborhood_admin!
      if current_user.superadmin?
        return
      end

      unless current_user.admin? && current_user.neighborhood_association_id.present?
        redirect_to root_path, alert: "Acceso denegado. Se requieren permisos de administración de junta de vecinos."
      end
    end

    def current_neighborhood_association
      @current_neighborhood_association ||= if session[:impersonated_neighborhood_association_id] && current_user.superadmin?
        NeighborhoodAssociation.find(session[:impersonated_neighborhood_association_id])
      else
        current_user.neighborhood_association
      end
    end
    helper_method :current_neighborhood_association
  end
end
