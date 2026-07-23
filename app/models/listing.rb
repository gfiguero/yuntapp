class Listing < ApplicationRecord
  include Filterable

  PUBLICATION_STATUSES = %w[pending_payment published].freeze
  PLATFORM_FEE_PERCENTAGE = 10
  PUBLICATION_PERIOD = 30.days

  class AlreadyPaidError < StandardError; end

  belongs_to :user
  belongs_to :category, optional: true
  belongs_to :neighborhood_association, optional: true

  before_save :compute_platform_fee, if: -> { amount.present? && platform_fee.nil? }

  validates :name, presence: true
  validates :publication_status, presence: true, inclusion: {in: PUBLICATION_STATUSES}
  validates :payment_id, uniqueness: true, allow_nil: true

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

  private

  def compute_platform_fee
    self.platform_fee = amount * PLATFORM_FEE_PERCENTAGE / 100
  end
end
