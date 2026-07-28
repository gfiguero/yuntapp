module Superadmin
  class AdministrationRequestsController < Superadmin::ApplicationController
    include Pagy::Method

    before_action :set_administration_request, only: %i[show approve reject]

    def index
      scope = AdministrationRequest.includes(:user, :neighborhood_association).order(created_at: :desc)
      @pagy, @administration_requests = pagy(scope)
    end

    def show
    end

    # BR-122/BR-128: solo el staff aprueba; la transacción crea junta/identidad/member/directiva.
    def approve
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
  end
end
