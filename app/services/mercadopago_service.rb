require "openssl"
require "mercadopago"
require "mercadopago/sdk"

# Wrapper sobre el SDK oficial de MercadoPago. Encapsula:
#   - Creación de Preferences (checkout)
#   - Consulta de payments
#   - Verificación de firma de webhooks (BR-072)
#
# El SDK se instancia bajo demanda usando el access_token configurado en
# `Rails.application.config.mercadopago[:access_token]`.
class MercadopagoService
  class ConfigurationError < StandardError; end

  def initialize(access_token: nil, webhook_secret: nil)
    @access_token = access_token || Rails.application.config.mercadopago[:access_token]
    @webhook_secret = webhook_secret || Rails.application.config.mercadopago[:webhook_secret]
  end

  # Crea una preference en MercadoPago y retorna el hash de respuesta.
  # back_urls y notification_url deben venir del controller (necesita request.url).
  def create_preference(certificate, success_url:, failure_url:, pending_url:, notification_url:)
    ensure_access_token!

    payload = {
      items: [
        {
          id: "cert-#{certificate.id}",
          title: I18n.t("payments.mercadopago.item_title", folio: certificate_label(certificate)),
          quantity: 1,
          currency_id: "CLP",
          unit_price: certificate.amount
        }
      ],
      external_reference: certificate.id.to_s,
      back_urls: {
        success: success_url,
        failure: failure_url,
        pending: pending_url
      },
      auto_return: "approved",
      notification_url: notification_url
    }

    response = sdk.preference.create(payload)
    response[:response]
  end

  # Consulta el estado actual de un pago vía MP API.
  def fetch_payment(payment_id)
    ensure_access_token!
    response = sdk.payment.get(payment_id)
    response[:response]
  end

  # Consulta un merchant_order (contiene payments anidados cuando el checkout
  # usa mercadopago con múltiples medios de pago parciales).
  def fetch_merchant_order(merchant_order_id)
    ensure_access_token!
    response = sdk.merchant_order.get(merchant_order_id)
    response[:response]
  end

  # Verifica la firma del webhook según el protocolo de MercadoPago.
  # Header `x-signature`: "ts=<timestamp>,v1=<hmac_hash>"
  # Header `x-request-id` (opcional): id de la request. MP solo lo envía en
  #   notificaciones v1.0 (WebHook). Feed v2.0 no lo incluye.
  # Manifest a firmar:
  #   Con request-id: "id:<data_id>;request-id:<x-request-id>;ts:<ts>;"
  #   Sin request-id: "id:<data_id>;ts:<ts>;"
  # Soporta v1 y v2 como prefijo del hash.
  def verify_signature(signature_header:, request_id: nil, data_id:)
    return false if @webhook_secret.blank?
    return false if signature_header.blank? || data_id.blank?

    parts = signature_header.to_s.split(",").map { |p| p.strip.split("=", 2) }.to_h
    ts = parts["ts"]
    received_hash = parts["v1"] || parts["v2"]

    return false if ts.blank? || received_hash.blank?

    manifest = if request_id.present?
      "id:#{data_id};request-id:#{request_id};ts:#{ts};"
    else
      "id:#{data_id};ts:#{ts};"
    end
    computed_hash = OpenSSL::HMAC.hexdigest("sha256", @webhook_secret, manifest)

    secure_compare(computed_hash, received_hash)
  end

  private

  def sdk
    @sdk ||= ::Mercadopago::SDK.new(@access_token)
  end

  def ensure_access_token!
    raise ConfigurationError, "MercadoPago access_token not configured" if @access_token.blank?
  end

  def certificate_label(certificate)
    certificate.folio.presence || "##{certificate.id}"
  end

  def secure_compare(a, b)
    return false if a.bytesize != b.bytesize
    ActiveSupport::SecurityUtils.secure_compare(a, b)
  end
end
