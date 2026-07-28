module Panel
  class ResidenceCertificatesController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :ensure_household_admin!
    before_action :ensure_active_member!, only: [:new, :create]
    before_action :set_residence_certificate, only: [:show, :download]

    # GET /panel/residence_certificates
    def index
      @residence_certificates = ResidenceCertificate
        .where(household_unit: current_user.household_unit)
        .order(created_at: :desc)
    end

    # GET /panel/residence_certificates/1
    def show
    end

    # GET /panel/residence_certificates/1/download
    # BR-091/BR-092: descarga bloqueada si el certificado está vencido o su
    # titular fue desactivado. El PDF nunca se sirve directo desde la vista.
    def download
      unless @residence_certificate.downloadable? && @residence_certificate.pdf_document.attached?
        redirect_to panel_residence_certificate_path(@residence_certificate),
          alert: I18n.t("panel.residence_certificates.flash.not_downloadable")
        return
      end

      redirect_to rails_blob_path(@residence_certificate.pdf_document, disposition: "attachment")
    end

    # GET /panel/residence_certificates/new
    def new
      @residence_certificate = ResidenceCertificate.new
      @approved_residencies = selectable_residencies
      @current_pricing = CertificatePricing.current_for(current_user.neighborhood_association)
    end

    # POST /panel/residence_certificates
    def create
      pricing = CertificatePricing.current_for(certificate_association)

      if pricing.blank?
        @residence_certificate = ResidenceCertificate.new
        @approved_residencies = selectable_residencies
        @current_pricing = nil
        flash.now[:alert] = I18n.t("panel.residence_certificates.flash.no_price")
        render :new, status: :unprocessable_content
        return
      end

      # Fuente única de "residente actual": el mismo current_residencies que ofrece
      # el selector (selectable_residencies). Un id que no corresponda a un residente
      # vigente resuelve a member nil y el save falla con error de validación.
      submitted_id = params[:residence_certificate][:member_id].to_i
      residency = current_user.household_unit.current_residencies.find { |r| r.id == submitted_id }
      member = residency&.verified_identity&.members&.approved&.find_by(neighborhood_association: certificate_association)

      @residence_certificate = ResidenceCertificate.new(
        member: member,
        household_unit: current_user.household_unit,
        neighborhood_association: certificate_association,
        purpose: params.require(:residence_certificate).permit(:purpose)[:purpose],
        amount: pricing.price
      )

      if @residence_certificate.save
        redirect_to panel_residence_certificate_path(@residence_certificate), notice: I18n.t("panel.residence_certificates.flash.requested")
      else
        @approved_residencies = selectable_residencies
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

    # BR-001/BR-091: solo un socio con Member aprobado en la junta puede
    # solicitar certificados. Un socio desactivado (BR-036) queda bloqueado
    # aunque su Residency siga aprobada.
    def ensure_active_member!
      active = current_user.verified_identity&.members&.approved
        &.exists?(neighborhood_association: certificate_association)

      unless active
        redirect_to panel_residence_certificates_path,
          alert: I18n.t("panel.residence_certificates.flash.member_inactive")
      end
    end

    def certificate_association
      @certificate_association ||= current_user.household_unit.neighborhood_delegation.neighborhood_association
    end

    # Solo residentes del domicilio con Member aprobado en la junta pueden ser
    # titulares de un certificado (excluye dependientes desactivados — BR-037).
    def selectable_residencies
      current_user.household_unit.current_residencies.select do |residency|
        residency.verified_identity.members.approved.exists?(neighborhood_association: certificate_association)
      end
    end
  end
end
