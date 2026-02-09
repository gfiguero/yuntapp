module Admin
  class ImpersonationsController < Admin::ApplicationController
    def stop
      session[:impersonated_neighborhood_association_id] = nil
      redirect_to superadmin_neighborhood_associations_path, notice: "Has dejado de administrar la junta de vecinos."
    end
  end
end
