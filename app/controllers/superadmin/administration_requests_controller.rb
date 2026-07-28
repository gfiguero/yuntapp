module Superadmin
  class AdministrationRequestsController < Superadmin::ApplicationController
    include Pagy::Method

    before_action :set_administration_request, only: %i[show approve reject]
    before_action :ensure_pending!, only: %i[approve reject]

    def index
      scope = AdministrationRequest.includes(:user, :neighborhood_association).order(created_at: :desc)
      @pagy, @administration_requests = pagy(scope)
    end

    def show
    end

    # BR-122/BR-128: solo el staff aprueba; la transacción crea junta/identidad/member/directiva.
    def approve
      # BR-129 (I3): si el RUN ya está verificado en OTRA identidad, la aprobación transfiere/
      # sobrescribe esa identidad. Exigir confirmación explícita del staff antes de proceder.
      if requires_run_confirmation? && params[:confirm_duplicate_run] != "1"
        redirect_to superadmin_administration_request_path(@administration_request),
          alert: I18n.t("superadmin.administration_requests.flash.confirm_run_required"), status: :see_other
        return
      end

      AdministrationApprovalService.approve!(@administration_request, approved_by: current_user)
      AdministrationRequestMailer.approved(@administration_request).deliver_later
      redirect_to superadmin_administration_request_path(@administration_request),
        notice: I18n.t("superadmin.administration_requests.flash.approved"), status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      redirect_to superadmin_administration_request_path(@administration_request),
        alert: e.message, status: :see_other
    end

    # BR-131: rechazo con motivo obligatorio.
    def reject
      reason = params.dig(:administration_request, :rejection_reason).to_s.strip
      if reason.blank?
        redirect_to superadmin_administration_request_path(@administration_request),
          alert: I18n.t("superadmin.administration_requests.flash.reason_required"), status: :see_other
        return
      end
      @administration_request.update!(status: "rejected", reviewed_by: current_user, reviewed_at: Time.current, rejection_reason: reason)
      AdministrationRequestMailer.rejected(@administration_request).deliver_later
      redirect_to superadmin_administration_request_path(@administration_request),
        notice: I18n.t("superadmin.administration_requests.flash.rejected"), status: :see_other
    end

    private

    def set_administration_request
      @administration_request = AdministrationRequest.find(params[:id])
    end

    def ensure_pending!
      unless @administration_request.pending?
        redirect_to superadmin_administration_request_path(@administration_request),
          alert: I18n.t("superadmin.administration_requests.flash.not_pending"), status: :see_other
      end
    end

    # El RUN ya existe verificado en una identidad que NO es la del solicitante
    # (el RUN es único en verified_identities — BR-012). Aprobar transferiría esa identidad.
    def requires_run_confirmation?
      run = @administration_request.run
      return false if run.blank?
      existing = VerifiedIdentity.find_by(run: run)
      existing.present? && existing.id != @administration_request.user.verified_identity_id
    end
    helper_method :requires_run_confirmation?
  end
end
