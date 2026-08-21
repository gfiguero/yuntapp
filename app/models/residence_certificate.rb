class ResidenceCertificate < ApplicationRecord
  include Filterable

  STATUSES = %w[pending_payment paid issued].freeze
  REVERTED_PAYMENT_STATUSES = %w[refunded charged_back].freeze
  MINIMUM_AMOUNT = 1000
  PLATFORM_FEE_PERCENTAGE = 10
  # BR-023: por ley, los certificados emitidos por juntas de vecinos duran 30 días.
  VALIDITY_PERIOD = 30.days
  VALIDATION_CODE_LENGTH = 8
  VALIDATION_CODE_ALPHABET = ("A".."Z").to_a - %w[O I] + ("2".."9").to_a # sin 0/O/1/I para evitar confusión visual (BR-074)

  class AlreadyPaidError < StandardError; end

  belongs_to :neighborhood_association
  belongs_to :member
  belongs_to :household_unit
  # BR-152: quién pidió el certificado, que no siempre es su titular — el
  # household_admin puede solicitarlo a nombre de un dependiente (BR-098).
  # `optional` porque los certificados anteriores a la columna no lo tienen.
  belongs_to :requested_by, class_name: "User", optional: true

  # BR-100: el historial de eventos de pago (#101) no se destruye.
  has_many :payment_events, as: :payable, dependent: :restrict_with_error

  has_one_attached :pdf_document

  after_initialize :set_default_status, if: :new_record?
  before_save :compute_platform_fee, if: -> { amount.present? && platform_fee.nil? }
  after_commit :enqueue_issuance_job, if: :should_enqueue_issuance?

  validates :status, presence: true, inclusion: {in: STATUSES}
  validate :immutable_once_issued, on: :update
  validates :purpose, presence: true
  validates :folio, uniqueness: {scope: :neighborhood_association_id, allow_blank: true}
  validates :amount, numericality: {only_integer: true, greater_than_or_equal_to: MINIMUM_AMOUNT}, allow_nil: true
  validates :payment_id, uniqueness: true, allow_nil: true
  validates :validation_token, uniqueness: true, allow_nil: true
  validates :validation_code, uniqueness: true, allow_nil: true

  scope :filter_by_status, ->(status) { where(status: status) }
  scope :filter_by_folio, ->(folio) { where.like(folio: "%#{folio}%") }
  scope :findable_publicly, -> { where(status: "issued") }

  # Busca un certificado para verificación pública aceptando token UUID o
  # código alfanumérico de 8 caracteres. Solo retorna certificados en estado
  # `issued` (BR-081). Case-insensitive para el código.
  def self.find_for_public_verification(identifier)
    return nil if identifier.blank?
    cleaned = identifier.to_s.strip
    return nil if cleaned.empty?

    if cleaned.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      findable_publicly.find_by(validation_token: cleaned.downcase)
    elsif cleaned.match?(/\A[A-Za-z0-9]{#{VALIDATION_CODE_LENGTH}}\z/o)
      findable_publicly.find_by(validation_code: cleaned.upcase)
    end
  end

  def pending_payment?
    status == "pending_payment"
  end

  def paid?
    status == "paid"
  end

  def issued?
    status == "issued"
  end

  def expired?
    expiration_date.present? && expiration_date < Date.current
  end

  # BR-141: un pago revertido por MP (refund/contracargo) invalida el certificado.
  def payment_reverted?
    REVERTED_PAYMENT_STATUSES.include?(payment_status)
  end

  # BR-091 (#107): la validez del certificado exige que el titular sea socio
  # APROBADO. Se expresa en positivo (`!member.approved?`) para cubrir cualquier
  # estado no-activo del Member (inactive, rejected, pending), no solo `inactive`.
  def holder_deactivated?
    !member.approved?
  end

  # BR-091/BR-092/BR-141: el PDF solo puede descargarse si el certificado está
  # emitido, vigente, su titular sigue activo y el pago no fue revertido.
  def downloadable?
    issued? && !expired? && !holder_deactivated? && !payment_reverted?
  end

  # BR-152: true cuando el certificado lo pidió alguien distinto de su titular
  # (BR-098, el household_admin a nombre de un dependiente). Falso también para
  # los certificados anteriores a la columna, que no tienen solicitante: no se
  # afirma lo que no se sabe.
  def requested_by_other?
    return false if requested_by.nil?

    requested_by.verified_identity_id != member.verified_identity_id
  end

  # RUN enmascarado para verificación pública (BR-078).
  # Formato: 12.XXX.XXX-K (preserva primer dígito y dígito verificador).
  FULLY_MASKED_RUN = "X.XXX.XXX-X"

  def masked_run
    raw = member&.run
    return nil if raw.blank?

    # Falla cerrado: un RUN que no viene en el formato normalizado (BR-010) se
    # enmascara por completo. Antes hacía `return raw`, o sea que un valor sin
    # guión —datos legacy o mal migrados— se publicaba **entero** en la página de
    # verificación, que es pública y no requiere login.
    return FULLY_MASKED_RUN unless raw.match?(/\A\d{7,8}-[0-9K]\z/)

    body, dv = raw.split("-")
    "#{body[0]}.XXX.XXX-#{dv}"
  end

  # Transición pending_payment → paid. Idempotente para el mismo payment_id (BR-071).
  # Si el certificado ya está pagado con otro payment_id, levanta AlreadyPaidError.
  #
  # Contempla `issued?` además de `paid?`: MP envía el merchant_order en dos
  # fases (opened + closed) y el `closed` re-procesa el mismo pago cuando el
  # certificado ya fue emitido. Ese re-proceso es un no-op limpio (mismo
  # payment_id) — NO debe intentar el `update!(status: "paid")` sobre un cert
  # inmutable (BR-008), que generaría un RecordInvalid espurio en los logs.
  # BR-141: las tres transiciones de estado del certificado (mark_as_paid!,
  # apply_mp_payment_status! e issue!) leen el estado y luego escriben. Sin
  # serializar, un webhook de reversión y el IssueCertificateJob podían operar
  # sobre la misma lectura de `paid` y pisarse: el job emitía mientras la
  # reversión devolvía a `pending_payment`. `with_lock` recarga el registro
  # dentro de una transacción, así que cada transición decide sobre el estado
  # vigente. (En SQLite el `FOR UPDATE` es no-op —Arel lo omite—, pero el motor
  # serializa las escrituras y la recarga dentro de la transacción es lo que
  # cierra la ventana read-then-write.)
  def mark_as_paid!(payment_id:, paid_at: Time.current)
    with_lock do
      next if (paid? || issued?) && self.payment_id == payment_id

      if (paid? || issued?) && self.payment_id != payment_id
        raise AlreadyPaidError, "Certificate ##{id} already paid with payment_id #{self.payment_id}"
      end

      update!(status: "paid", payment_id: payment_id, paid_at: paid_at)
    end
    self
  end

  # Registra el estado crudo de un pago no-`approved` de MP y aplica la reacción
  # de negocio (BR-141, BR-073). Idempotente por estado. `approved` NO pasa por
  # aquí — el webhook usa mark_as_paid!.
  def apply_mp_payment_status!(mp_status)
    with_lock do
      next if payment_status == mp_status

      if REVERTED_PAYMENT_STATUSES.include?(mp_status) && paid?
        # Asunción: refund/contracargo se trata como reversión TOTAL (el modelo de
        # negocio usa montos únicos, sin refunds parciales). Si MP habilitara
        # refunds parciales, revisar esta lógica.
        #
        # BR-004: no hace falta recalcular `platform_fee` al revertir. A
        # diferencia de `Listing`, el `amount` del certificado se captura al
        # crearlo y no se re-captura nunca (no hay ruta que lo reescriba), así
        # que el fee del re-pago es el mismo 10% del mismo monto.
        update!(payment_status: mp_status, status: "pending_payment")
      else
        update!(payment_status: mp_status)
      end
    end
    self
  end

  # Cantidad máxima de reintentos ante colisión de folio por emisión concurrente
  # de la misma junta (#98).
  FOLIO_MAX_ATTEMPTS = 5

  FOLIO_PREFIX = "CR"

  # Transición paid → issued. Genera folio, tokens y fecha de vencimiento atómicamente (BR-062, BR-074).
  # Idempotente: si ya está issued, retorna sin cambios.
  #
  # #98: el folio se deriva de un contador secuencial por junta. Dos emisiones
  # concurrentes de la misma junta pueden computar el mismo número; ante la
  # colisión (índice único association+folio) se limpia el folio y se reintenta
  # recalculando el siguiente número libre, en vez de quedar atascado en `paid`.
  def issue!(issue_date: Date.current)
    # BR-141: el lock recarga el estado antes de decidir, de modo que una
    # reversión concurrente que devolvió el certificado a `pending_payment`
    # aborta la emisión limpiamente en lugar de emitir un documento inválido.
    with_lock do
      next if issued?
      raise "Cannot issue certificate ##{id}: status is #{status}, must be paid" unless paid?
      raise "Cannot issue certificate ##{id}: junta sin RUT (no constituida legalmente, BR-120)" if neighborhood_association.rut.blank?

      attempts = 0
      begin
        attempts += 1
        # Con el índice (association, folio_year, folio_sequence) la colisión
        # ya no implica que el folio sea el problema: puede ser un folio
        # preexistente —único como string— cuyo `folio_sequence` recién
        # calculado choca con otro certificado. Solo el folio construido EN
        # ESTE intento debe descartarse en el rescue; uno que ya viniera en el
        # registro (defensa contra doble emisión) debe sobrevivir al retry.
        folio_built_this_attempt = folio.blank?
        transaction(requires_new: true) do
          year = issue_date.year
          sequence = folio_sequence || next_folio_sequence(year)

          assign_attributes(
            folio_year: folio_year || year,
            folio_sequence: sequence,
            folio: folio.presence || build_folio(year, sequence),
            validation_token: validation_token.presence || SecureRandom.uuid,
            validation_code: validation_code.presence || generate_validation_code,
            issue_date: issue_date,
            expiration_date: issue_date + VALIDITY_PERIOD,
            issued_at: Time.current,
            status: "issued"
          )
          save!
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
        raise unless folio_collision?(e) && attempts < FOLIO_MAX_ATTEMPTS
        self.folio = nil if folio_built_this_attempt
        self.folio_sequence = nil
        retry
      end
    end

    self
  end

  private

  def set_default_status
    self.status ||= "pending_payment"
  end

  # BR-004: Yuntapp retiene exactamente el 10%. `amount` es entero (CLP sin
  # decimales), así que redondeamos al peso más cercano en vez de truncar por
  # división entera (que sub-cobraba en montos no múltiplos de 10 — #99).
  def compute_platform_fee
    return if amount.blank?
    self.platform_fee = (amount * PLATFORM_FEE_PERCENTAGE / 100.0).round
  end

  # BR-008: el certificado emitido es inmutable en sus campos persistidos.
  # Excepción intencional: adjuntar/reemplazar el `pdf_document` es parte del
  # proceso de emisión (ver IssueCertificateJob) y no se considera mutación
  # del certificado, por eso permitimos cambios que solo afecten attachments.
  # `payment_status` registra eventos de MP posteriores a la emisión (refund/
  # chargeback, BR-141) y no forma parte del contenido inmutable (BR-008).
  def immutable_once_issued
    return unless status_in_database == "issued"
    return if (changed - ["payment_status"]).empty?
    errors.add(:base, :immutable)
  end

  def should_enqueue_issuance?
    saved_change_to_status? && status == "paid"
  end

  def enqueue_issuance_job
    IssueCertificateJob.perform_later(id)
  end

  # Correlativo siguiente de la junta para ese año. Consulta agregada sobre la
  # columna entera: sin parseo de strings y sin cargar los folios en memoria.
  def next_folio_sequence(year)
    max = self.class
      .where(neighborhood_association_id: neighborhood_association_id, folio_year: year)
      .maximum(:folio_sequence) || 0
    max + 1
  end

  # El folio es la representación del dato, no el dato. Ver BR-006.
  def build_folio(year, sequence)
    format("%s-%04d-%04d-%05d", FOLIO_PREFIX, year, neighborhood_association_id, sequence)
  end

  # ¿El error proviene de una colisión del folio (índice único association+folio
  # o la validación de unicidad)? Distingue el race de folio (#98) de cualquier
  # otro fallo, que debe propagarse sin reintento.
  def folio_collision?(error)
    case error
    when ActiveRecord::RecordNotUnique
      # SQLite (BD de prod) reporta las columnas en el mensaje: tanto
      # "...residence_certificates.folio" como
      # "...residence_certificates.folio_sequence" contienen "folio". El match
      # por substring cubre ambos índices, pero se deja explícito para que no
      # dependa del azar de los nombres. NO matchea payment_id/validation_*.
      error.message.include?("folio") || error.message.include?("folio_sequence")
    when ActiveRecord::RecordInvalid
      error.record.errors.key?(:folio)
    else
      false
    end
  end

  def generate_validation_code
    10.times do
      candidate = Array.new(VALIDATION_CODE_LENGTH) { VALIDATION_CODE_ALPHABET.sample }.join
      return candidate unless self.class.exists?(validation_code: candidate)
    end
    raise "Could not generate unique validation_code after 10 attempts"
  end
end
