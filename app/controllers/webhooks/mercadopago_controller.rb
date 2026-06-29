module Webhooks
  class MercadopagoController < ActionController::Base
    # Endpoint público de MercadoPago. No usa el layout principal ni Devise.
    # Seguridad: verifica firma HMAC `x-signature` (BR-072), idempotencia por
    # payment_id (BR-071), consulta el estado real a la API de MP antes de
    # marcar como pagado.
    skip_forgery_protection

    # POST /webhooks/mercadopago
    def create
      data_id = params.dig(:data, :id) || params[:id] || params[:resource]
      data_id = extract_payment_id(data_id)

      unless valid_signature?(data_id)
        Rails.logger.warn("MercadoPago webhook: invalid signature (data_id=#{data_id})")
        head :unauthorized
        return
      end

      if data_id.blank?
        Rails.logger.warn("MercadoPago webhook: missing data_id in payload")
        head :ok
        return
      end

      # Idempotencia (BR-071): si ya procesamos este payment_id, respondemos OK sin re-procesar
      if ResidenceCertificate.exists?(payment_id: data_id)
        Rails.logger.info("MercadoPago webhook: payment_id #{data_id} already processed")
        head :ok
        return
      end

      payment = mercadopago.fetch_payment(data_id)
      process_payment(payment, data_id)

      head :ok
    rescue MercadopagoService::ConfigurationError => e
      Rails.logger.error("MercadoPago webhook: service not configured (#{e.message})")
      head :service_unavailable
    rescue => e
      Rails.logger.error("MercadoPago webhook: unexpected error (#{e.class}: #{e.message})")
      head :ok
    end

    private

    def mercadopago
      @mercadopago ||= MercadopagoService.new
    end

    def valid_signature?(data_id)
      mercadopago.verify_signature(
        signature_header: request.headers["x-signature"],
        request_id: request.headers["x-request-id"],
        data_id: data_id
      )
    end

    def process_payment(payment, data_id)
      return unless payment.is_a?(Hash)

      external_reference = payment["external_reference"] || payment[:external_reference]
      status = payment["status"] || payment[:status]

      if external_reference.blank?
        Rails.logger.warn("MercadoPago webhook: missing external_reference for #{data_id}")
        return
      end

      certificate = ResidenceCertificate.find_by(id: external_reference)
      unless certificate
        Rails.logger.warn("MercadoPago webhook: certificate ##{external_reference} not found")
        return
      end

      case status.to_s
      when "approved"
        certificate.mark_as_paid!(payment_id: data_id)
        Rails.logger.info("MercadoPago webhook: certificate ##{certificate.id} marked paid (payment_id=#{data_id})")
      else
        Rails.logger.info("MercadoPago webhook: payment #{data_id} status=#{status} for certificate ##{certificate.id} — no transition")
      end
    end

    # MP envía el id del payment de varias formas: `data: { id: 123 }`,
    # `id: 123`, o `resource: "/v1/payments/123"`. Normalizamos.
    def extract_payment_id(value)
      return nil if value.blank?
      str = value.to_s
      if str.include?("/")
        str.split("/").last
      else
        str
      end
    end
  end
end
