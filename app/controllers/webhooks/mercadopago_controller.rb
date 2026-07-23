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

      # La firma HMAC solo está presente en notificaciones v1.0 (WebHook).
      # Feed v2.0 envía topic=payment y topic=merchant_order sin x-signature.
      # En ambos casos confiamos en la consulta a la API de MP como validación
      # secundaria. Solo rechazamos si x-signature está presente pero es inválida.
      signature_present = request.headers["x-signature"].present?
      if signature_present && !valid_signature?(data_id)
        Rails.logger.warn("MercadoPago webhook: invalid signature for #{topic} (data_id=#{data_id})")
        head :unauthorized
        return
      end

      if !signature_present
        Rails.logger.info("MercadoPago webhook: no signature for topic=#{topic} (data_id=#{data_id}), proceeding")
      end

      case topic
      when "payment"
        process_payment_notification(data_id)
      when "merchant_order"
        process_merchant_order(data_id)
      when "subscription_preapproval"
        process_subscription_preapproval(data_id)
      when "subscription_authorized_payment"
        process_subscription_authorized_payment(data_id)
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
      if payment_already_processed?(payment_id)
        Rails.logger.info("MercadoPago webhook: payment_id #{payment_id} already processed")
        return
      end

      payment = mercadopago.fetch_payment(payment_id)
      return unless payment.is_a?(Hash)
      mark_payable_paid(payment, payment_id)
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
        next if pid.nil? || payment_already_processed?(pid.to_s)

        payment = mercadopago.fetch_payment(pid.to_s)
        mark_payable_paid(payment, pid.to_s)
      end
    end

    # topic=subscription_preapproval: cambió el estado de una suscripción
    # (autorizada, pausada o cancelada por el usuario/MP). Sincroniza el
    # estado local (BR-088).
    def process_subscription_preapproval(preapproval_id)
      preapproval = mercadopago.fetch_preapproval(preapproval_id)
      return unless preapproval.is_a?(Hash)

      external_reference = (preapproval["external_reference"] || preapproval[:external_reference]).to_s
      status = (preapproval["status"] || preapproval[:status]).to_s

      listing = Listing.find_by(preapproval_id: preapproval_id)
      listing ||= Listing.find_by(id: external_reference.delete_prefix("listing-")) if external_reference.start_with?("listing-")

      unless listing
        Rails.logger.warn("MercadoPago webhook: no listing for preapproval #{preapproval_id}")
        return
      end

      if Listing::SUBSCRIPTION_STATUSES.include?(status)
        listing.update!(preapproval_id: preapproval_id, subscription_status: status)
        Rails.logger.info("MercadoPago webhook: listing ##{listing.id} subscription #{status} (preapproval=#{preapproval_id})")
      else
        Rails.logger.info("MercadoPago webhook: preapproval #{preapproval_id} status=#{status} — no sync")
      end
    end

    # topic=subscription_authorized_payment: cobro recurrente de una
    # suscripción. Si el payment anidado está aprobado, extiende la vigencia
    # de la publicación (BR-089).
    def process_subscription_authorized_payment(authorized_payment_id)
      invoice = mercadopago.fetch_authorized_payment(authorized_payment_id)
      return unless invoice.is_a?(Hash)

      preapproval_id = (invoice["preapproval_id"] || invoice[:preapproval_id]).to_s
      payment = invoice["payment"] || invoice[:payment] || {}
      payment_id = (payment["id"] || payment[:id]).to_s
      payment_status = (payment["status"] || payment[:status]).to_s

      if payment_id.blank?
        Rails.logger.info("MercadoPago webhook: authorized_payment #{authorized_payment_id} without payment yet")
        return
      end

      if payment_already_processed?(payment_id)
        Rails.logger.info("MercadoPago webhook: payment_id #{payment_id} already processed")
        return
      end

      listing = Listing.find_by(preapproval_id: preapproval_id)
      unless listing
        external_reference = (invoice["external_reference"] || invoice[:external_reference]).to_s
        listing = Listing.find_by(id: external_reference.delete_prefix("listing-")) if external_reference.start_with?("listing-")
      end

      unless listing
        Rails.logger.warn("MercadoPago webhook: no listing for authorized_payment #{authorized_payment_id} (preapproval=#{preapproval_id})")
        return
      end

      case payment_status
      when "approved"
        listing.renew_from_subscription!(payment_id: payment_id)
        Rails.logger.info("MercadoPago webhook: listing ##{listing.id} renewed until #{listing.published_until} (payment_id=#{payment_id})")
      else
        Rails.logger.info("MercadoPago webhook: authorized_payment #{authorized_payment_id} payment status=#{payment_status} for listing ##{listing.id} — no renewal")
      end
    end

    # Idempotencia compartida (BR-071/BR-087): un payment_id ya registrado en
    # certificados o publicaciones no se vuelve a procesar.
    def payment_already_processed?(payment_id)
      ResidenceCertificate.exists?(payment_id: payment_id) || Listing.exists?(payment_id: payment_id)
    end

    # Enruta el pago según external_reference:
    #   "listing-<id>" → publicación del marketplace (BR-083)
    #   "<id>" a secas → certificado de residencia (formato original)
    def mark_payable_paid(payment, payment_id)
      return unless payment.is_a?(Hash)

      external_reference = (payment["external_reference"] || payment[:external_reference]).to_s
      status = payment["status"] || payment[:status]

      if external_reference.blank?
        Rails.logger.warn("MercadoPago webhook: missing external_reference for #{payment_id}")
        return
      end

      amount = payment["transaction_amount"] || payment[:transaction_amount]

      if external_reference.start_with?("listing-")
        mark_listing_paid(external_reference.delete_prefix("listing-"), status, payment_id, amount)
      else
        mark_certificate_paid(external_reference, status, payment_id, amount)
      end
    end

    def mark_certificate_paid(certificate_id, status, payment_id, amount)
      certificate = ResidenceCertificate.find_by(id: certificate_id)
      unless certificate
        Rails.logger.warn("MercadoPago webhook: certificate ##{certificate_id} not found")
        return
      end

      # BR-090: el monto pagado debe coincidir exactamente con el monto del
      # certificado. Rechaza pagos de otro monto (manipulación o pagos
      # obsoletos de otra operación con external_reference coincidente).
      unless amount_matches?(amount, certificate.amount)
        Rails.logger.warn("MercadoPago webhook: payment #{payment_id} amount #{amount.inspect} != certificate ##{certificate.id} amount #{certificate.amount.inspect} — rejected")
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

    def mark_listing_paid(listing_id, status, payment_id, amount)
      listing = Listing.find_by(id: listing_id)
      unless listing
        Rails.logger.warn("MercadoPago webhook: listing ##{listing_id} not found")
        return
      end

      # BR-090: mismo control de monto que los certificados.
      unless amount_matches?(amount, listing.amount)
        Rails.logger.warn("MercadoPago webhook: payment #{payment_id} amount #{amount.inspect} != listing ##{listing.id} amount #{listing.amount.inspect} — rejected")
        return
      end

      case status.to_s
      when "approved"
        listing.mark_as_paid!(payment_id: payment_id)
        Rails.logger.info("MercadoPago webhook: listing ##{listing.id} published (payment_id=#{payment_id})")
      else
        Rails.logger.info("MercadoPago webhook: payment #{payment_id} status=#{status} for listing ##{listing.id} — no transition")
      end
    end

    def amount_matches?(paid_amount, expected_amount)
      return false if paid_amount.nil? || expected_amount.nil?
      paid_amount.to_d == expected_amount.to_d
    end

    # Extrae el último segmento de una URL o devuelve el valor tal cual.
    def extract_id(value)
      return nil if value.blank?
      str = value.to_s
      str.include?("/") ? str.split("/").last : str
    end
  end
end
