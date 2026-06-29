module Panel
  class PaymentsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :ensure_household_admin!
    before_action :set_certificate, only: :new
    before_action :ensure_pending_payment!, only: :new

    # GET /panel/payments/new?certificate_id=X
    # Crea una preference en MercadoPago y redirige al checkout.
    def new
      preference = mercadopago.create_preference(
        @certificate,
        success_url: success_panel_payments_url,
        failure_url: failure_panel_payments_url,
        pending_url: pending_panel_payments_url,
        notification_url: webhooks_mercadopago_url
      )

      init_point = preference["init_point"] || preference[:init_point]

      if init_point.blank?
        Rails.logger.error("MercadoPago returned no init_point: #{preference.inspect}")
        redirect_to panel_residence_certificate_path(@certificate),
          alert: I18n.t("panel.payments.flash.preference_failed")
        return
      end

      redirect_to init_point, allow_other_host: true
    rescue MercadopagoService::ConfigurationError => e
      Rails.logger.error("MercadoPago not configured: #{e.message}")
      redirect_to panel_residence_certificate_path(@certificate),
        alert: I18n.t("panel.payments.flash.misconfigured")
    end

    # GET /panel/payments/success — back_url cuando MP confirma pago aprobado.
    def success
      @certificate = find_certificate_by_external_reference
    end

    # GET /panel/payments/failure — back_url cuando MP rechaza el pago.
    def failure
      @certificate = find_certificate_by_external_reference
    end

    # GET /panel/payments/pending — back_url cuando el pago queda pendiente.
    def pending
      @certificate = find_certificate_by_external_reference
    end

    private

    def mercadopago
      @mercadopago ||= MercadopagoService.new
    end

    def set_certificate
      @certificate = ResidenceCertificate
        .where(household_unit: current_user.household_unit)
        .find(params[:certificate_id])
    end

    def find_certificate_by_external_reference
      external_reference = params[:external_reference].presence
      return nil if external_reference.blank?
      ResidenceCertificate
        .where(household_unit: current_user.household_unit)
        .find_by(id: external_reference)
    end

    def ensure_pending_payment!
      return if @certificate.pending_payment?
      redirect_to panel_residence_certificate_path(@certificate),
        alert: I18n.t("panel.payments.flash.not_pending_payment")
    end

    def ensure_household_admin!
      return if current_user.household_admin?
      redirect_to panel_root_path, alert: I18n.t("panel.payments.flash.not_household_admin")
    end
  end
end
