module Panel
  class DependentsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :ensure_household_admin!
    before_action :ensure_active_member!

    # GET /panel/dependents
    def index
      family_group = current_user.family_group

      @pending_requests = IdentityVerificationRequest
        .dependent_requests
        .where(family_group: family_group, status: "pending")
        .order(created_at: :desc)

      @rejected_requests = IdentityVerificationRequest
        .dependent_requests
        .where(family_group: family_group, status: "rejected")
        .order(created_at: :desc)

      @dependent_members = Member
        .dependent
        .joins(:verified_identity)
        .joins("INNER JOIN residencies ON residencies.verified_identity_id = verified_identities.id")
        .where(residencies: {family_group_id: family_group.id, status: "approved"})
        .where(neighborhood_association: current_user.neighborhood_association)
        .distinct
    end

    # GET /panel/dependents/new
    def new
      @identity_verification_request = IdentityVerificationRequest.new
    end

    # POST /panel/dependents
    def create
      @identity_verification_request = IdentityVerificationRequest.new(dependent_params)
      @identity_verification_request.assign_attributes(
        dependent: true,
        status: "pending",
        family_group: current_user.family_group,
        requested_by: current_user,
        neighborhood_association: current_user.neighborhood_association
      )

      if @identity_verification_request.save
        redirect_to panel_dependents_path, notice: I18n.t("panel.dependents.flash.created")
      else
        render :new, status: :unprocessable_content
      end
    end

    private

    def dependent_params
      params.require(:identity_verification_request).permit(
        :first_name, :last_name, :run, :phone,
        identity_documents: []
      )
    end

    def ensure_household_admin!
      unless current_user.household_admin?
        redirect_to panel_root_path, alert: I18n.t("panel.dependents.flash.not_household_admin")
      end
    end

    # BR-091/BR-099: la desactivación del socio (BR-036) debe cortar el acceso
    # operativo. `household_admin?` no basta: se apoya en la Residency, que por
    # BR-038 no cambia de estado al desactivar el Member, así que seguía
    # devolviendo true. Un socio dado de baja podía registrar dependientes y, al
    # aprobarlos el admin, se le recreaba un Member(approved) — deshaciendo su
    # propia desactivación. Mismo gate que en residence_certificates.
    def ensure_active_member!
      active = current_user.verified_identity&.members&.approved
        &.exists?(neighborhood_association: current_user.neighborhood_association)

      unless active
        redirect_to panel_root_path, alert: I18n.t("panel.dependents.flash.member_inactive")
      end
    end
  end
end
