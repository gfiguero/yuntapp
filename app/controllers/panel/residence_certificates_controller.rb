module Panel
  class ResidenceCertificatesController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :ensure_household_admin!
    before_action :set_residence_certificate, only: :show

    # GET /panel/residence_certificates
    def index
      @residence_certificates = ResidenceCertificate
        .where(household_unit: current_user.household_unit)
        .order(created_at: :desc)
    end

    # GET /panel/residence_certificates/1
    def show
    end

    # GET /panel/residence_certificates/new
    def new
      @residence_certificate = ResidenceCertificate.new
      @approved_residencies = current_user.household_unit.approved_residencies
    end

    # POST /panel/residence_certificates
    def create
      residency = current_user.household_unit.approved_residencies.find(params[:residence_certificate][:member_id])
      member = residency.verified_identity.members.find_by(neighborhood_association: current_user.neighborhood_association)

      @residence_certificate = ResidenceCertificate.new(
        member: member,
        household_unit: current_user.household_unit,
        neighborhood_association: current_user.household_unit.neighborhood_delegation.neighborhood_association,
        purpose: params.require(:residence_certificate).permit(:purpose)[:purpose]
      )

      if @residence_certificate.save
        redirect_to panel_residence_certificate_path(@residence_certificate), notice: I18n.t("panel.residence_certificates.flash.requested")
      else
        @approved_residencies = current_user.household_unit.approved_residencies
        render :new, status: :unprocessable_content
      end
    end

    private

    def set_residence_certificate
      @residence_certificate = ResidenceCertificate.where(household_unit: current_user.household_unit).find(params[:id])
    end

    def ensure_household_admin!
      unless current_user.household_admin?
        redirect_to panel_root_path, alert: "Debes ser administrador del domicilio para solicitar certificados."
      end
    end
  end
end
