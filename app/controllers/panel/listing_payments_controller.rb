module Panel
  # Pago para habilitar una publicación del marketplace (BR-083).
  # Mismo mecanismo que el pago de certificados: preference de MercadoPago
  # Checkout Pro + confirmación vía webhook.
  class ListingPaymentsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :set_listing, only: :new
    before_action :ensure_payable!, only: :new
    before_action :ensure_priced_association!, only: :new

    # GET /panel/listing_payments/new?listing_id=X
    # Captura el precio vigente de la junta del socio (snapshot, BR-084),
    # crea la preference y redirige al checkout.
    def new
      @listing.update!(amount: @pricing.price, platform_fee: nil, neighborhood_association: @association)

      preference = mercadopago.create_listing_preference(
        @listing,
        success_url: success_panel_listing_payments_url,
        failure_url: failure_panel_listing_payments_url,
        pending_url: pending_panel_listing_payments_url,
        notification_url: webhooks_mercadopago_url
      )

      init_point = preference["init_point"] || preference[:init_point]

      if init_point.blank?
        Rails.logger.error("MercadoPago returned no init_point: #{preference.inspect}")
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.payments.flash.preference_failed")
        return
      end

      redirect_to init_point, allow_other_host: true
    rescue MercadopagoService::ConfigurationError => e
      Rails.logger.error("MercadoPago not configured: #{e.message}")
      redirect_to panel_listing_path(@listing),
        alert: I18n.t("panel.payments.flash.misconfigured")
    end

    # GET /panel/listing_payments/success
    def success
      @listing = find_listing_by_external_reference
    end

    # GET /panel/listing_payments/failure
    def failure
      @listing = find_listing_by_external_reference
    end

    # GET /panel/listing_payments/pending
    def pending
      @listing = find_listing_by_external_reference
    end

    private

    def mercadopago
      @mercadopago ||= MercadopagoService.new
    end

    def set_listing
      @listing = current_user.listings.find(params[:listing_id])
    end

    def find_listing_by_external_reference
      external_reference = params[:external_reference].to_s.delete_prefix("listing-")
      return nil if external_reference.blank?
      current_user.listings.find_by(id: external_reference)
    end

    def ensure_payable!
      return if @listing.payable?
      redirect_to panel_listing_path(@listing),
        alert: I18n.t("panel.listing_payments.flash.not_payable")
    end

    # El pago requiere ser socio de una junta (el 90% del monto es para ella)
    # y que esa junta tenga precio de publicación vigente (BR-084).
    def ensure_priced_association!
      @association = current_user.member&.neighborhood_association
      if @association.nil?
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_payments.flash.not_member")
        return
      end

      @pricing = ListingPricing.current_for(@association)
      if @pricing.nil?
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_payments.flash.no_price")
      end
    end
  end
end
