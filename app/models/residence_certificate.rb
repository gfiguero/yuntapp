class ResidenceCertificate < ApplicationRecord
  include Filterable

  STATUSES = %w[pending_payment paid issued].freeze

  belongs_to :neighborhood_association
  belongs_to :member
  belongs_to :household_unit
  belongs_to :approved_by, class_name: "User", optional: true

  after_initialize :set_default_status, if: :new_record?

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :purpose, presence: true
  validates :folio, uniqueness: { scope: :neighborhood_association_id, allow_blank: true }

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

  private

  def set_default_status
    self.status ||= "pending_payment"
  end
end
