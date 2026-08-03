module Panel
  class AdministrationRequestsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :redirect_if_admin, only: %i[new create]
    before_action :redirect_if_active_request, only: %i[new create]

    def show
      @administration_request = current_user.administration_requests.order(created_at: :desc).first
      redirect_to new_panel_administration_request_path unless @administration_request
    end

    def new
      @administration_request = AdministrationRequest.new
      @cascading_data = build_cascading_data
      @current_memberships = current_active_memberships
    end

    def create
      @administration_request = AdministrationRequest.new(administration_request_params)
      @administration_request.user = current_user
      @administration_request.status = "pending"

      if @administration_request.save
        notify_existing_admins
        AdministrationRequestMailer.submitted(@administration_request).deliver_later
        redirect_to panel_administration_request_path, notice: I18n.t("panel.administration_requests.flash.submitted")
      else
        @cascading_data = build_cascading_data
        @current_memberships = current_active_memberships
        render :new, status: :unprocessable_content
      end
    end

    def cancel
      current_user.administration_requests.pending.first&.cancel!
      redirect_to new_panel_administration_request_path, notice: I18n.t("panel.administration_requests.flash.cancelled")
    end

    private

    def administration_request_params
      params.require(:administration_request).permit(
        :neighborhood_association_id, :region_id, :commune_id, :proposed_association_name,
        :organization_rut, :position, :first_name, :last_name, :run, :phone,
        :directiva_validity_document, identity_documents: []
      )
    end

    # BR-136: un usuario solo administra una junta; si ya es admin, no puede solicitar otra.
    def redirect_if_admin
      redirect_to panel_root_path, alert: I18n.t("panel.administration_requests.flash.already_admin") if current_user.admin?
    end

    # BR-134: una solicitud activa a la vez.
    def redirect_if_active_request
      redirect_to panel_administration_request_path if current_user.administration_requests.active.exists?
    end

    # BR-130: avisar a los admins vigentes de la junta objetivo.
    def notify_existing_admins
      junta = @administration_request.neighborhood_association
      return unless junta

      User.where(admin: true, neighborhood_association_id: junta.id).find_each do |admin|
        AdministrationRequestMailer.notify_existing_admin(admin, @administration_request).deliver_later
      end
    end

    # BR-137: el solicitante debe saber, antes de enviar, que ser aprobado como
    # admin de otra junta desactivará su membresía actual, invalidará los
    # certificados que tenga allí (BR-091) y desactivará a sus residentes
    # dependientes (BR-099). Devuelve las juntas donde hoy es socio aprobado.
    def current_active_memberships
      current_user.verified_identity&.members&.approved
        &.includes(:neighborhood_association)&.map(&:neighborhood_association) || []
    end

    # Mismo patrón que Panel::OnboardingController#build_cascading_data.
    def build_cascading_data
      associations_by_commune = NeighborhoodAssociation.active.where.not(commune_id: nil).order(:name).group_by(&:commune_id)
      communes = Commune.where(id: associations_by_commune.keys).order(:name).includes(:region)
      communes.group_by(&:region).map do |region, region_communes|
        {
          id: region.id, name: region.name,
          communes: region_communes.sort_by(&:name).map do |commune|
            {id: commune.id, name: commune.name,
             associations: (associations_by_commune[commune.id] || []).map { |a| {id: a.id, name: a.name} }}
          end
        }
      end.sort_by { |r| r[:name] }
    end
  end
end
