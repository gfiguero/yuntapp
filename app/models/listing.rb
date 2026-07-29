class Listing < ApplicationRecord
  include Filterable

  PUBLICATION_STATUSES = %w[pending_payment published].freeze
  # Estados de la suscripción de auto-renovación en MercadoPago (BR-088).
  # pending: preapproval creada, esperando autorización del usuario en MP.
  SUBSCRIPTION_STATUSES = %w[pending authorized paused cancelled].freeze
  REVERTED_PAYMENT_STATUSES = %w[refunded charged_back].freeze
  PLATFORM_FEE_PERCENTAGE = 10
  PUBLICATION_PERIOD = 30.days

  class AlreadyPaidError < StandardError; end

  belongs_to :user
  belongs_to :category, optional: true
  belongs_to :neighborhood_association, optional: true

  # BR-100: el historial de eventos de pago (#101) no se destruye.
  has_many :payment_events, as: :payable, dependent: :restrict_with_error

  before_save :compute_platform_fee, if: -> { amount.present? && platform_fee.nil? }

  validates :name, presence: true
  validates :publication_status, presence: true, inclusion: {in: PUBLICATION_STATUSES}
  validates :payment_id, uniqueness: true, allow_nil: true
  validates :preapproval_id, uniqueness: true, allow_nil: true
  validates :subscription_status, inclusion: {in: SUBSCRIPTION_STATUSES}, allow_nil: true
  # BR-085 (#109): el snapshot amount/platform_fee es inmutable MIENTRAS la
  # publicación está vigente. Al vencer (publication_expired?) sí puede
  # re-capturarse el precio para la renovación (BR-086).
  validate :pricing_snapshot_immutable_while_published, on: :update

  scope :published, -> { where(publication_status: "published").where("published_until >= ?", Date.current) }

  def pending_payment?
    publication_status == "pending_payment"
  end

  # Publicada y con vigencia al día (BR-086: 30 días desde el pago).
  def published?
    publication_status == "published" && published_until.present? && published_until >= Date.current
  end

  def publication_expired?
    publication_status == "published" && published_until.present? && published_until < Date.current
  end

  # Puede iniciarse un pago: nunca pagada, o vencida (renovación).
  def payable?
    pending_payment? || publication_expired?
  end

  # Transición a published tras el pago confirmado por MercadoPago (BR-083).
  # Idempotente para el mismo payment_id (BR-087). Una renovación (publicación
  # vencida) acepta un nuevo payment_id y extiende la vigencia.
  def mark_as_paid!(payment_id:, paid_at: Time.current)
    if self.payment_id == payment_id && published?
      return self
    end

    if published? && self.payment_id != payment_id
      raise AlreadyPaidError, "Listing ##{id} already published with payment_id #{self.payment_id}"
    end

    update!(
      publication_status: "published",
      payment_id: payment_id,
      paid_at: paid_at,
      published_until: paid_at.to_date + PUBLICATION_PERIOD
    )
    self
  end

  def payment_reverted?
    REVERTED_PAYMENT_STATUSES.include?(payment_status)
  end

  # Espejo de ResidenceCertificate#apply_mp_payment_status! para publicaciones
  # (BR-141). Un pago revertido despublica; los demás estados solo se registran.
  # La guardia mira el VALOR de columna (no `published?`, que excluye vencidas):
  # un chargeback sobre un listing ya vencido igual debe corregir el estado.
  def apply_mp_payment_status!(mp_status)
    return self if payment_status == mp_status

    if REVERTED_PAYMENT_STATUSES.include?(mp_status) && publication_status == "published"
      # Asunción: refund/contracargo se trata como reversión TOTAL (el modelo de
      # negocio usa montos únicos, sin refunds parciales). Si MP habilitara
      # refunds parciales, revisar esta lógica.
      update!(payment_status: mp_status, publication_status: "pending_payment", published_until: nil)
    else
      update!(payment_status: mp_status)
    end
    self
  end

  def subscription_active?
    subscription_status == "authorized"
  end

  # Puede activar auto-renovación: pagable y sin suscripción vigente.
  # Un intento abandonado (pending) puede reiniciarse con una nueva preapproval.
  def subscribable?
    payable? && !subscription_active?
  end

  # Renovación por cobro recurrente aprobado (BR-089). Idempotente por
  # payment_id. Extiende 30 días desde el vencimiento vigente si la
  # publicación está al día (el cobro llega antes de vencer), o desde la
  # fecha del cobro si estaba vencida.
  def renew_from_subscription!(payment_id:, paid_at: Time.current)
    return self if self.payment_id == payment_id

    base = published? ? published_until : paid_at.to_date
    update!(
      publication_status: "published",
      payment_id: payment_id,
      paid_at: paid_at,
      published_until: base + PUBLICATION_PERIOD
    )
    self
  end

  private

  # BR-085: Yuntapp retiene exactamente el 10%. `amount` es entero (CLP sin
  # decimales); redondeamos al peso más cercano en vez de truncar (#99).
  def compute_platform_fee
    self.platform_fee = (amount * PLATFORM_FEE_PERCENTAGE / 100.0).round
  end

  # #109/BR-085: el snapshot de precio no puede cambiar mientras la publicación
  # estaba VIGENTE (según el estado persistido). Una publicación vencida sí puede
  # re-capturar el precio para renovarse (BR-086), por eso se mira el estado en BD.
  def pricing_snapshot_immutable_while_published
    return unless publication_status_in_database == "published"
    return if published_until_in_database.nil? || published_until_in_database < Date.current

    if amount_changed? || platform_fee_changed?
      errors.add(:base, "No se puede modificar el precio de una publicación vigente")
    end
  end
end
