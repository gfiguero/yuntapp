module Panel
  class ResidenceCertificatesController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :ensure_household_admin!
    before_action :ensure_active_member!, only: [:new, :create]
    before_action :ensure_association_constituted!, only: [:new, :create]
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
    # BR-091/BR-092/BR-141: descarga bloqueada si el certificado está vencido, su
    # titular fue desactivado o el pago fue revertido. El PDF nunca se sirve
    # directo desde la vista.
    #
    # El contenido se envía con `send_data` en vez de redirigir al blob: la URL
    # de Active Storage depende solo del signed_id (no de `current_user` ni de
    # `downloadable?`) y con el servicio Disk no expira, así que quien guardara
    # esa URL seguía descargando el certificado después de ser desactivado, de
    # que venciera o de que le revirtieran el pago. Aquí cada descarga vuelve a
    # pasar por la autorización.
    def download
      unless @residence_certificate.downloadable? && @residence_certificate.pdf_document.attached?
        redirect_to panel_residence_certificate_path(@residence_certificate),
          alert: I18n.t("panel.residence_certificates.flash.not_downloadable")
        return
      end

      send_data @residence_certificate.pdf_document.download,
        filename: "#{@residence_certificate.folio}.pdf",
        type: "application/pdf",
        disposition: "attachment"
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

      # Fuente única de titulares válidos: exactamente la misma lista que ofrece el
      # selector. Antes esto releía `current_residencies` por su cuenta, sin el filtro
      # por núcleo familiar, así que un `member_id` manipulado emitía un certificado a
      # nombre de un conviviente de otro `FamilyGroup` (BR-041). Un id que no esté en
      # la lista resuelve a member nil y el save falla con error de validación.
      submitted_id = params[:residence_certificate][:member_id].to_i
      residency = selectable_residencies.find { |r| r.id == submitted_id }
      member = residency&.verified_identity&.members&.approved&.find_by(neighborhood_association: certificate_association)

      @residence_certificate = ResidenceCertificate.new(
        member: member,
        household_unit: current_user.household_unit,
        neighborhood_association: certificate_association,
        purpose: params.require(:residence_certificate).permit(:purpose)[:purpose],
        amount: pricing.price,
        # BR-152: nunca viene del formulario, siempre de la sesión. El titular
        # (`member`) puede ser un dependiente; el solicitante es quien opera.
        requested_by: current_user
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

    # BR-148: una junta sin RUT no puede emitir (BR-120), así que tampoco puede
    # recibir solicitudes. Sin este guard el socio solicitaba, pagaba, y el
    # certificado quedaba atascado en `paid` para siempre: `issue!` aborta por
    # falta de RUT, el job se rinde y BR-063 prohíbe la devolución.
    def ensure_association_constituted!
      return if certificate_association&.rut.present?

      redirect_to panel_residence_certificates_path,
        alert: I18n.t("panel.residence_certificates.flash.association_without_rut")
    end

    def certificate_association
      @certificate_association ||= current_user.household_unit.neighborhood_delegation.neighborhood_association
    end

    # Titulares posibles de un certificado: los residentes del **núcleo familiar**
    # del solicitante con Member aprobado en la junta (excluye dependientes
    # desactivados — BR-037).
    #
    # BR-041/BR-098: el filtro por `family_group` es de seguridad, no cosmético.
    # Un `HouseholdUnit` es una dirección física y puede alojar varias familias sin
    # relación entre sí (BR-040). Sin este filtro, el jefe de un núcleo veía el RUN
    # de los otros convivientes y podía emitir certificados oficiales a su nombre.
    # Es la única fuente de titulares válidos: `create` la reusa para que un
    # `member_id` manipulado no eluda el filtro del selector.
    def selectable_residencies
      family_group = current_user.family_group
      return [] if family_group.blank?

      current_user.household_unit.current_residencies.select do |residency|
        residency.family_group_id == family_group.id &&
          residency.verified_identity.members.approved.exists?(neighborhood_association: certificate_association)
      end
    end
  end
end
