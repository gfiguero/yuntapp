class ResidenceCertificate < ApplicationRecord
  include Filterable

  STATUSES = %w[pending_payment paid issued].freeze
  MINIMUM_AMOUNT = 1000
  PLATFORM_FEE_PERCENTAGE = 10

  class AlreadyPaidError < StandardError; end

  belongs_to :neighborhood_association
  belongs_to :member
  belongs_to :household_unit
  belongs_to :approved_by, class_name: "User", optional: true

  after_initialize :set_default_status, if: :new_record?
  before_save :compute_platform_fee, if: -> { amount.present? && platform_fee.nil? }

  validates :status, presence: true, inclusion: {in: STATUSES}
  validate :immutable_once_issued, on: :update
  validates :purpose, presence: true
  validates :folio, uniqueness: {scope: :neighborhood_association_id, allow_blank: true}
  validates :amount, numericality: {only_integer: true, greater_than_or_equal_to: MINIMUM_AMOUNT}, allow_nil: true
  validates :payment_id, uniqueness: true, allow_nil: true

  scope :filter_by_status, ->(status) { where(status: status) }
  scope :filter_by_folio, ->(folio) { where.like(folio: "%#{folio}%") }

  def pending_payment?
    status == "pending_payment"
  end

  def paid?
    status == "paid"
  end

  def issued?
    status == "issued"
  end

  def generate_folio!
    sequence = self.class.where(neighborhood_association_id: neighborhood_association_id).maximum(:id) || 0
    update!(folio: "CR-#{neighborhood_association_id}-#{sequence + 1}")
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

  private

  def set_default_status
    self.status ||= "pending_payment"
  end

  def compute_platform_fee
    return if amount.blank?
    self.platform_fee = amount * PLATFORM_FEE_PERCENTAGE / 100
  end

  def immutable_once_issued
    errors.add(:base, :immutable) if status_in_database == "issued"
  end
end
