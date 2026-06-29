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
      @current_pricing = CertificatePricing.current_for(current_user.neighborhood_association)
    end

    # POST /panel/residence_certificates
    def create
      association = current_user.household_unit.neighborhood_delegation.neighborhood_association
      pricing = CertificatePricing.current_for(association)

      if pricing.blank?
        @residence_certificate = ResidenceCertificate.new
        @approved_residencies = current_user.household_unit.approved_residencies
        @current_pricing = nil
        flash.now[:alert] = I18n.t("panel.residence_certificates.flash.no_price")
        render :new, status: :unprocessable_content
        return
      end

      residency = current_user.household_unit.approved_residencies.find(params[:residence_certificate][:member_id])
      member = residency.verified_identity.members.find_by(neighborhood_association: association)

      @residence_certificate = ResidenceCertificate.new(
        member: member,
        household_unit: current_user.household_unit,
        neighborhood_association: association,
        purpose: params.require(:residence_certificate).permit(:purpose)[:purpose],
        amount: pricing.price
      )

      if @residence_certificate.save
        redirect_to panel_residence_certificate_path(@residence_certificate), notice: I18n.t("panel.residence_certificates.flash.requested")
      else
        @approved_residencies = current_user.household_unit.approved_residencies
        @current_pricing = pricing
        render :new, status: :unprocessable_content
      end
    end

    private

    def set_residence_certificate
      @residence_certificate = ResidenceCertificate.where(household_unit: current_user.household_unit).find(params[:id])
    end

    def ensure_household_admin!
      unless current_user.household_admin?
        redirect_to panel_root_path, alert: I18n.t("panel.residence_certificates.flash.not_household_admin")
      end
    end
  end
end
