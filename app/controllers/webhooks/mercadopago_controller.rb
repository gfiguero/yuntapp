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

      # BR-072 (#106): la doc oficial de MP indica que, con la clave secreta
      # configurada, MercadoPago SIEMPRE firma las notificaciones Webhook
      # (payment, merchant_order y suscripciones; la única excepción es QR, que
      # no usamos). Por lo tanto, si hay secret configurado exigimos firma válida
      # y rechazamos con 401 cuando falta o no valida — cerrando la vía de un POST
      # forjado sin firma. Si NO hay secret configurado (dev/test) no se puede
      # validar: se procesa apoyándose en la re-consulta a la API de MP.
      if webhook_secret_configured?
        unless request.headers["x-signature"].present? && valid_signature?(data_id)
          Rails.logger.warn("MercadoPago webhook: missing or invalid signature for #{topic} (data_id=#{data_id}) — rejected")
          head :unauthorized
          return
        end
      else
        Rails.logger.info("MercadoPago webhook: no webhook_secret configured, skipping signature check (topic=#{topic})")
      end

      case topic
      when "payment"
        process_payment_notification(data_id)
      when "merchant_order", "topic_merchant_order_wh"
        # "topic_merchant_order_wh" es el nombre del evento de órdenes
        # comerciales cuando la notificación viene del webhook configurado
        # en el panel de MP (el canal legacy usa "merchant_order").
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
    rescue ResidenceCertificate::AlreadyPaidError, Listing::AlreadyPaidError,
      ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # #100: errores DETERMINISTAS — el recurso ya fue pagado con otro payment_id,
      # una colisión de unicidad (idempotencia efectiva: otro webhook ya lo
      # procesó) o el certificado es inmutable por estar emitido. Reintentar no
      # cambiaría el resultado, así que respondemos 200 para que MercadoPago NO
      # reintente en loop. Solo los fallos transitorios llegan al rescue de abajo.
      Rails.logger.warn("MercadoPago webhook: deterministic no-op (#{e.class}: #{e.message})")
      head :ok
    rescue => e
      # #100/BR-071/BR-073: un error TRANSITORIO (timeout a la API de MP, deadlock
      # de SQLite, fallo al encolar el job) NO debe tragarse con 200 — MP no
      # reintentaría y un pago aprobado real quedaría sin marcar. Devolvemos 500
      # para que MercadoPago reintente. Los no-op deterministas (pago no aprobado,
      # monto que no coincide, recurso inexistente, firma inválida) ya retornan
      # sin excepción y responden 200/401 antes de llegar aquí.
      Rails.logger.error("MercadoPago webhook: unexpected error (#{e.class}: #{e.message})")
      head :internal_server_error
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

    # #106: hay clave secreta de webhook configurada (producción). Solo entonces
    # exigimos firma (MP siempre firma cuando el secret está configurado).
    def webhook_secret_configured?
      Rails.application.config.mercadopago[:webhook_secret].present?
    end

    # topic=payment: data_id es un payment_id. Siempre consultamos el estado
    # real; la idempotencia es por estado (ver mark_payable_paid), no por
    # "payment_id ya visto" — un refund/contracargo reusa el payment_id.
    def process_payment_notification(payment_id)
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
        next if pid.nil?

        payment = mercadopago.fetch_payment(pid.to_s)
        mark_payable_paid(payment, pid.to_s)
      end

      record_order_closed(order, merchant_order_id) if (order["status"] || order[:status]).to_s == "closed"
    end

    # MP cierra el merchant_order (opened→closed) cuando el pago cubrió el total.
    # Registramos el cierre como PaymentEvent (status "order_closed", clave el
    # merchant_order_id) para tener trazabilidad del ciclo completo de la orden,
    # sin ensuciar los logs. Idempotente por el índice único (payment_id, status).
    def record_order_closed(order, merchant_order_id)
      external_reference = (order["external_reference"] || order[:external_reference]).to_s
      return if external_reference.blank?

      payable = resolve_payable(external_reference)
      return unless payable

      record_payment_event(payable, payment_id: merchant_order_id.to_s, status: "order_closed", amount: nil)
      Rails.logger.info("MercadoPago webhook: merchant_order #{merchant_order_id} closed for #{payable.class}##{payable.id}")
    end

    # Resuelve el payable (certificado o publicación) desde el external_reference:
    #   "listing-<id>" → Listing (BR-083); "<id>" a secas → ResidenceCertificate.
    def resolve_payable(external_reference)
      if external_reference.start_with?("listing-")
        Listing.find_by(id: external_reference.delete_prefix("listing-"))
      else
        ResidenceCertificate.find_by(id: external_reference)
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
        # #101: idempotencia histórica por (payment_id, status). Un reintento
        # tardío del webhook de un cobro ya aplicado no re-renueva (antes el
        # payment_id se perdía al sobrescribirse en renew_from_subscription!).
        if payment_already_processed?(payment_id, "approved")
          Rails.logger.info("MercadoPago webhook: subscription payment #{payment_id} already processed")
          return
        end

        # BR-090: el cobro recurrente debe coincidir exactamente con el monto
        # snapshot de la publicación, igual que el pago único. Rechaza montos
        # distintos o payment_ids obsoletos de otra operación cuyo
        # preapproval/external_reference coincida (protección contra manipulación).
        amount = payment["transaction_amount"] || payment[:transaction_amount]
        unless amount_matches?(amount, listing.amount)
          Rails.logger.warn("MercadoPago webhook: subscription payment #{payment_id} amount #{amount.inspect} != listing ##{listing.id} amount #{listing.amount.inspect} — no renewal")
          return
        end

        # #101: renovación y registro del evento (el gate de idempotencia) commitean
        # atómicamente. Si fallara entre ambos, el rollback deja el listing sin renovar
        # y sin evento → el reintento de MP re-renueva limpio. Así la idempotencia NO
        # depende de la guarda `payment_id` de renew_from_subscription! (mero atajo).
        ActiveRecord::Base.transaction do
          listing.renew_from_subscription!(payment_id: payment_id)
          record_payment_event(listing, payment_id: payment_id, status: "approved", amount: amount)
        end
        Rails.logger.info("MercadoPago webhook: listing ##{listing.id} renewed until #{listing.published_until} (payment_id=#{payment_id})")
      else
        Rails.logger.info("MercadoPago webhook: authorized_payment #{authorized_payment_id} payment status=#{payment_status} for listing ##{listing.id} — no renewal")
      end
    end

    # Idempotencia histórica (#101/BR-071/BR-087): un (payment_id, status) ya
    # registrado en payment_events no se vuelve a procesar. La clave incluye el
    # status para no bloquear un refund/contracargo posterior del mismo pago
    # (reconciliación con Batch G: los refunds reusan el payment_id del approved).
    def payment_already_processed?(payment_id, status)
      PaymentEvent.exists?(payment_id: payment_id, status: status)
    end

    # Registra el evento de pago (log histórico + idempotencia). Idempotente por
    # el índice único (payment_id, status). `amount` es best-effort: en eventos
    # no-approved (refund/contracargo/rechazo) MP no siempre lo envía y puede ser
    # nil — no es load-bearing (la idempotencia es por (payment_id, status)).
    def record_payment_event(payable, payment_id:, status:, amount:)
      PaymentEvent.find_or_create_by(payment_id: payment_id, status: status) do |event|
        event.payable = payable
        event.amount = amount
        event.processed_at = Time.current
      end
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

      case status.to_s
      when "approved"
        # BR-090: el monto solo se valida en la transición a pagado. Las
        # reversiones (refund/contracargo) deben procesarse siempre, sin gate de monto.
        unless amount_matches?(amount, certificate.amount)
          Rails.logger.warn("MercadoPago webhook: payment #{payment_id} amount #{amount.inspect} != certificate ##{certificate.id} amount #{certificate.amount.inspect} — rejected")
          return
        end
        certificate.mark_as_paid!(payment_id: payment_id)
        certificate.update!(payment_status: "approved") unless certificate.payment_status == "approved"
        record_payment_event(certificate, payment_id: payment_id, status: "approved", amount: amount)
        Rails.logger.info("MercadoPago webhook: certificate ##{certificate.id} marked paid (payment_id=#{payment_id})")
      else
        handle_non_approved(certificate, status.to_s, payment_id, amount)
      end
    end

    def mark_listing_paid(listing_id, status, payment_id, amount)
      listing = Listing.find_by(id: listing_id)
      unless listing
        Rails.logger.warn("MercadoPago webhook: listing ##{listing_id} not found")
        return
      end

      case status.to_s
      when "approved"
        # BR-090: mismo control de monto que los certificados. Solo en la
        # transición a pagado; reversiones deben procesarse sin gate de monto.
        unless amount_matches?(amount, listing.amount)
          Rails.logger.warn("MercadoPago webhook: payment #{payment_id} amount #{amount.inspect} != listing ##{listing.id} amount #{listing.amount.inspect} — rejected")
          return
        end
        listing.mark_as_paid!(payment_id: payment_id)
        listing.update!(payment_status: "approved") unless listing.payment_status == "approved"
        record_payment_event(listing, payment_id: payment_id, status: "approved", amount: amount)
        Rails.logger.info("MercadoPago webhook: listing ##{listing.id} published (payment_id=#{payment_id})")
      else
        handle_non_approved(listing, status.to_s, payment_id, amount)
      end
    end

    # #125/#127: aplica un estado no-approved de MP al payable. Idempotente por
    # estado (apply_mp_payment_status! no hace nada si el estado no cambió).
    # Ante un pago revertido (refund/contracargo) notifica al staff (BR-141).
    def handle_non_approved(payable, status, payment_id, amount = nil)
      # Nota: read-then-write sin lock. En SQLite (prod) las escrituras
      # serializan, así que el peor caso ante dos webhooks casi simultáneos del
      # mismo pago es un correo de reversión duplicado al staff (benigno). Con un
      # motor más concurrente, envolver en with_lock.
      changed = payable.payment_status != status
      payable.apply_mp_payment_status!(status)
      unless changed
        Rails.logger.info("MercadoPago webhook: #{payable.class}##{payable.id} status=#{status} unchanged — no-op")
        return
      end

      # #101: log histórico del evento (refund/contracargo/rechazo/en revisión).
      record_payment_event(payable, payment_id: payment_id, status: status, amount: amount)

      if ResidenceCertificate::REVERTED_PAYMENT_STATUSES.include?(status)
        Rails.logger.error("MercadoPago webhook: PAYMENT REVERTED #{payable.class}##{payable.id} status=#{status} (payment_id=#{payment_id})")
        notify_staff_of_reversal(payable)
      else
        Rails.logger.info("MercadoPago webhook: #{payable.class}##{payable.id} payment_status=#{status} registered")
      end
    end

    def notify_staff_of_reversal(payable)
      User.where(superadmin: true).find_each do |staff|
        PaymentReversalMailer.staff_alert(staff, payable).deliver_later if staff.email.present?
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
