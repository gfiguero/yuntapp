class ResidenceCertificate < ApplicationRecord
  include Filterable

  STATUSES = %w[pending_payment paid issued].freeze
  MINIMUM_AMOUNT = 1000
  PLATFORM_FEE_PERCENTAGE = 10
  VALIDITY_PERIOD = 6.months
  VALIDATION_CODE_LENGTH = 8
  VALIDATION_CODE_ALPHABET = ("A".."Z").to_a + ("2".."9").to_a # sin 0/O/1/I para evitar confusión visual

  class AlreadyPaidError < StandardError; end

  belongs_to :neighborhood_association
  belongs_to :member
  belongs_to :household_unit
  belongs_to :approved_by, class_name: "User", optional: true

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

  # Transición paid → issued. Genera folio, tokens y fecha de vencimiento atómicamente (BR-062, BR-074).
  # Idempotente: si ya está issued, retorna sin cambios.
  def issue!(issue_date: Date.current)
    return self if issued?
    raise "Cannot issue certificate ##{id}: status is #{status}, must be paid" unless paid?

    transaction do
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

  # BR-008: el certificado emitido es inmutable en sus campos persistidos.
  # Excepción intencional: adjuntar/reemplazar el `pdf_document` es parte del
  # proceso de emisión (ver IssueCertificateJob) y no se considera mutación
  # del certificado, por eso permitimos cambios que solo afecten attachments.
  def immutable_once_issued
    return unless status_in_database == "issued"
    return if changed.empty?
    errors.add(:base, :immutable)
  end

  def should_enqueue_issuance?
    saved_change_to_status? && status == "paid"
  end

  def enqueue_issuance_job
    IssueCertificateJob.perform_later(id)
  end

  def next_folio
    sequence = self.class.where(neighborhood_association_id: neighborhood_association_id).maximum(:id) || 0
    "CR-#{neighborhood_association_id}-#{sequence + 1}"
  end

  def generate_validation_code
    10.times do
      candidate = Array.new(VALIDATION_CODE_LENGTH) { VALIDATION_CODE_ALPHABET.sample }.join
      return candidate unless self.class.exists?(validation_code: candidate)
    end
    raise "Could not generate unique validation_code after 10 attempts"
  end
end
