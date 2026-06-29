require "openssl"

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

  # Verifica la firma del webhook según el protocolo de MercadoPago.
  # Header `x-signature`: "ts=<timestamp>,v1=<hmac_hash>"
  # Header `x-request-id`: id de la request
  # Manifest a firmar: "id:<data_id>;request-id:<x-request-id>;ts:<ts>;"
  def verify_signature(signature_header:, request_id:, data_id:)
    return false if @webhook_secret.blank?
    return false if signature_header.blank? || request_id.blank? || data_id.blank?

    parts = signature_header.to_s.split(",").map { |p| p.strip.split("=", 2) }.to_h
    ts = parts["ts"]
    received_hash = parts["v1"]

    return false if ts.blank? || received_hash.blank?

    manifest = "id:#{data_id};request-id:#{request_id};ts:#{ts};"
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
