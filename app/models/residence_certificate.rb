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
  belongs_to :approved_by, class_name: "User", optional: true

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

  # BR-091: la desactivación del socio (BR-036) invalida sus certificados
  # mientras permanezca inactivo — no se pueden descargar y la verificación
  # pública los muestra como no válidos.
  def holder_deactivated?
    member.inactive?
  end

  # BR-091/BR-092/BR-141: el PDF solo puede descargarse si el certificado está
  # emitido, vigente, su titular sigue activo y el pago no fue revertido.
  def downloadable?
    issued? && !expired? && !holder_deactivated? && !payment_reverted?
  end

  # RUN enmascarado para verificación pública (BR-078).
  # Formato: 12.XXX.XXX-K (preserva primer dígito y dígito verificador).
  def masked_run
    raw = member&.run
    return nil if raw.blank?

    body, dv = raw.split("-")
    return raw if body.nil? || dv.nil?

    first_digit = body[0]
    "#{first_digit}.XXX.XXX-#{dv}"
  end

  # Transición pending_payment → paid. Idempotente para el mismo payment_id (BR-071).
  # Si el certificado ya está pagado con otro payment_id, levanta AlreadyPaidError.
  def mark_as_paid!(payment_id:, paid_at: Time.current)
    if paid? && self.payment_id == payment_id
      return self
    end

    if paid? && self.payment_id != payment_id
      raise AlreadyPaidError, "Certificate ##{id} already paid with payment_id #{self.payment_id}"
    end

    update!(status: "paid", payment_id: payment_id, paid_at: paid_at)
    self
  end

  # Registra el estado crudo de un pago no-`approved` de MP y aplica la reacción
  # de negocio (BR-141, BR-073). Idempotente por estado. `approved` NO pasa por
  # aquí — el webhook usa mark_as_paid!.
  def apply_mp_payment_status!(mp_status)
    return self if payment_status == mp_status

    if REVERTED_PAYMENT_STATUSES.include?(mp_status) && paid?
      # Asunción: refund/contracargo se trata como reversión TOTAL (el modelo de
      # negocio usa montos únicos, sin refunds parciales). Si MP habilitara
      # refunds parciales, revisar esta lógica.
      update!(payment_status: mp_status, status: "pending_payment")
    else
      update!(payment_status: mp_status)
    end
    self
  end

  # Cantidad máxima de reintentos ante colisión de folio por emisión concurrente
  # de la misma junta (#98).
  FOLIO_MAX_ATTEMPTS = 5

  # Transición paid → issued. Genera folio, tokens y fecha de vencimiento atómicamente (BR-062, BR-074).
  # Idempotente: si ya está issued, retorna sin cambios.
  #
  # #98: el folio se deriva de un contador secuencial por junta. Dos emisiones
  # concurrentes de la misma junta pueden computar el mismo número; ante la
  # colisión (índice único association+folio) se limpia el folio y se reintenta
  # recalculando el siguiente número libre, en vez de quedar atascado en `paid`.
  def issue!(issue_date: Date.current)
    return self if issued?
    raise "Cannot issue certificate ##{id}: status is #{status}, must be paid" unless paid?
    raise "Cannot issue certificate ##{id}: junta sin RUT (no constituida legalmente, BR-120)" if neighborhood_association.rut.blank?

    attempts = 0
    begin
      attempts += 1
      transaction(requires_new: true) do
        assign_attributes(
          folio: folio.presence || next_folio,
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
      self.folio = nil
      retry
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

  # Siguiente folio secuencial POR JUNTA (BR-006). Se basa en el mayor número
  # de folio ya emitido por la junta (parseando el sufijo de `CR-{assoc}-{n}`),
  # no en `maximum(:id)` global, que producía folios no secuenciales por junta
  # y, al no cambiar entre reintentos, dejaba el certificado atascado (#98).
  def next_folio
    prefix = "CR-#{neighborhood_association_id}-"
    last = self.class
      .where(neighborhood_association_id: neighborhood_association_id)
      .where.not(folio: nil)
      .pluck(:folio)
      .map { |f| f.to_s.delete_prefix(prefix).to_i }
      .max || 0
    "#{prefix}#{last + 1}"
  end

  # ¿El error proviene de una colisión del folio (índice único association+folio
  # o la validación de unicidad)? Distingue el race de folio (#98) de cualquier
  # otro fallo, que debe propagarse sin reintento.
  def folio_collision?(error)
    case error
    when ActiveRecord::RecordNotUnique
      # SQLite (BD de prod) reporta el nombre de columna en el mensaje
      # ("UNIQUE constraint failed: ...residence_certificates.folio"), así que
      # matcheamos "folio". Depende de que la columna se llame `folio`; si se
      # renombrara, actualizar este match. NO matchea payment_id/validation_*.
      error.message.include?("folio")
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
