module Panel
  # Auto-renovación de publicaciones vía Suscripciones de MercadoPago
  # (preapproval, BR-088). El usuario autoriza una vez y MP cobra cada mes;
  # cada cobro aprobado extiende la vigencia (webhook, BR-089).
  class ListingSubscriptionsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :set_listing, only: [:new, :create, :cancel]

    # GET /panel/listing_subscriptions/new?listing_id=X
    # Muestra el formulario para confirmar el email de la cuenta MercadoPago
    # que se usará como payer_email de la suscripción (BR-142).
    def new
      unless @listing.subscribable?
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_subscriptions.flash.not_subscribable")
        return
      end
      return unless ensure_priced_association!

      @payer_email = current_user.mercadopago_email.presence || current_user.email
    end

    # POST /panel/listing_subscriptions?listing_id=X
    # Guarda el email confirmado, captura el precio (snapshot, BR-084/BR-088),
    # crea la preapproval con ese payer_email y redirige a MP para autorizar.
    def create
      unless @listing.subscribable?
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_subscriptions.flash.not_subscribable")
        return
      end
      return unless ensure_priced_association!

      email = params[:mercadopago_email].to_s.strip
      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        redirect_to new_panel_listing_subscription_path(listing_id: @listing.id),
          alert: I18n.t("panel.listing_subscriptions.flash.invalid_email")
        return
      end

      current_user.update!(mercadopago_email: email)
      @listing.update!(amount: @pricing.price, platform_fee: nil, neighborhood_association: @association)

      preapproval = mercadopago.create_listing_subscription(
        @listing,
        payer_email: email,
        back_url: success_panel_listing_subscriptions_url
      )

      init_point = preapproval["init_point"] || preapproval[:init_point]
      preapproval_id = (preapproval["id"] || preapproval[:id]).to_s

      if init_point.blank? || preapproval_id.blank?
        Rails.logger.error("MercadoPago returned no init_point/id for preapproval: #{preapproval.inspect}")
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_subscriptions.flash.subscription_failed", email: email)
        return
      end

      @listing.update!(preapproval_id: preapproval_id, subscription_status: "pending")
      redirect_to init_point, allow_other_host: true
    rescue MercadopagoService::ConfigurationError => e
      Rails.logger.error("MercadoPago not configured: #{e.message}")
      redirect_to panel_listing_path(@listing),
        alert: I18n.t("panel.payments.flash.misconfigured")
    end

    # GET /panel/listing_subscriptions/success — back_url tras autorizar en MP.
    def success
      preapproval_id = params[:preapproval_id].presence
      @listing = current_user.listings.find_by(preapproval_id: preapproval_id) if preapproval_id
    end

    # DELETE /panel/listing_subscriptions/cancel?listing_id=X
    # Cancela la suscripción en MP. La vigencia ya pagada se conserva (BR-089).
    def cancel
      if @listing.preapproval_id.blank? || @listing.subscription_status == "cancelled"
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_subscriptions.flash.no_subscription")
        return
      end

      mercadopago.cancel_preapproval(@listing.preapproval_id)
      @listing.update!(subscription_status: "cancelled")
      redirect_to panel_listing_path(@listing),
        notice: I18n.t("panel.listing_subscriptions.flash.cancelled")
    rescue MercadopagoService::ConfigurationError => e
      Rails.logger.error("MercadoPago not configured: #{e.message}")
      redirect_to panel_listing_path(@listing),
        alert: I18n.t("panel.payments.flash.misconfigured")
    end

    private

    def mercadopago
      @mercadopago ||= MercadopagoService.new
    end

    def set_listing
      @listing = current_user.listings.find(params[:listing_id])
    end

    # Mismo requisito que el pago único (BR-084): socio activo y junta con
    # precio de publicación vigente. Retorna false si redirigió.
    def ensure_priced_association!
      @association = current_user.member&.neighborhood_association
      if @association.nil?
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_payments.flash.not_member")
        return false
      end

      @pricing = ListingPricing.current_for(@association)
      if @pricing.nil?
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_payments.flash.no_price")
        return false
      end

      true
    end
  end
end
