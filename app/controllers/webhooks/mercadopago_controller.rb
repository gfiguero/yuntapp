module Webhooks
  class MercadopagoController < ActionController::Base
    # Endpoint público de MercadoPago. No usa el layout principal ni Devise.
    # Seguridad: verifica firma HMAC `x-signature` (BR-072), idempotencia por
    # payment_id (BR-071), consulta el estado real a la API de MP antes de
    # marcar como pagado.
    #
    # MP envía notificaciones de dos tipos:
    #   topic=payment       → data_id es un payment_id directamente
    #   topic=merchant_order → data_id es un merchant_order_id (contiene payments anidados)
    skip_forgery_protection

    # POST /webhooks/mercadopago
    def create
      topic = params[:topic] || params[:type]
      raw_id = params.dig(:data, :id) || params[:id] || params[:resource]
      data_id = extract_id(raw_id)

      if data_id.blank?
        Rails.logger.warn("MercadoPago webhook: missing data_id in payload")
        head :ok
        return
      end

      # La firma HMAC solo está presente en notificaciones topic=payment.
      # merchant_order llega sin x-signature ni x-request-id. En ese caso
      # confiamos en la consulta a la API de MP como validación secundaria.
      unless valid_signature?(data_id)
        if topic == "payment"
          Rails.logger.warn("MercadoPago webhook: invalid signature for payment (data_id=#{data_id})")
          head :unauthorized
          return
        end
        Rails.logger.info("MercadoPago webhook: no signature for topic=#{topic} (data_id=#{data_id}), proceeding")
      end

      case topic
      when "payment"
        process_payment_notification(data_id)
      when "merchant_order"
        process_merchant_order(data_id)
      else
        Rails.logger.info("MercadoPago webhook: unhandled topic=#{topic} (data_id=#{data_id})")
      end

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

    # topic=payment: data_id es un payment_id directamente.
    def process_payment_notification(payment_id)
      if ResidenceCertificate.exists?(payment_id: payment_id)
        Rails.logger.info("MercadoPago webhook: payment_id #{payment_id} already processed")
        return
      end

      payment = mercadopago.fetch_payment(payment_id)
      return unless payment.is_a?(Hash)
      mark_certificate_paid(payment, payment_id)
    end

    # topic=merchant_order: data_id es un merchant_order_id.
    # Buscamos los payments dentro del merchant_order y los procesamos
    # individualmente (cada payment tiene su propio payment_id).
    def process_merchant_order(merchant_order_id)
      order = mercadopago.fetch_merchant_order(merchant_order_id)
      return unless order.is_a?(Hash)

      payments = order["payments"] || []
      payments.each do |payment_entry|
        pid = payment_entry["id"]
        next if pid.nil? || ResidenceCertificate.exists?(payment_id: pid.to_s)

        payment = mercadopago.fetch_payment(pid.to_s)
        mark_certificate_paid(payment, pid.to_s)
      end
    end

    def mark_certificate_paid(payment, payment_id)
      return unless payment.is_a?(Hash)

      external_reference = payment["external_reference"] || payment[:external_reference]
      status = payment["status"] || payment[:status]

      if external_reference.blank?
        Rails.logger.warn("MercadoPago webhook: missing external_reference for #{payment_id}")
        return
      end

      certificate = ResidenceCertificate.find_by(id: external_reference)
      unless certificate
        Rails.logger.warn("MercadoPago webhook: certificate ##{external_reference} not found")
        return
      end

      case status.to_s
      when "approved"
        certificate.mark_as_paid!(payment_id: payment_id)
        Rails.logger.info("MercadoPago webhook: certificate ##{certificate.id} marked paid (payment_id=#{payment_id})")
      else
        Rails.logger.info("MercadoPago webhook: payment #{payment_id} status=#{status} for certificate ##{certificate.id} — no transition")
      end
    end

    # Extrae el último segmento de una URL o devuelve el valor tal cual.
    def extract_id(value)
      return nil if value.blank?
      str = value.to_s
      str.include?("/") ? str.split("/").last : str
    end
  end
end
