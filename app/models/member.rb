class Member < ApplicationRecord
  include Filterable

  STATUSES = %w[pending approved rejected inactive].freeze

  belongs_to :verified_identity
  belongs_to :neighborhood_association

  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :board_members, dependent: :destroy
  has_many :residence_certificates, dependent: :destroy

  validates :verified_identity_id, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :deactivation_reason, presence: true, if: -> { inactive? }

  delegate :name, :run, :phone, :email, :first_name, :last_name, to: :verified_identity, allow_nil: true

  scope :filter_by_status, ->(status) { where(status: status) }
  scope :filter_by_name, ->(name) { joins(:verified_identity).where("verified_identities.first_name LIKE :q OR verified_identities.last_name LIKE :q", q: "%#{name}%") }
  scope :filter_by_run, ->(run) { joins(:verified_identity).where("verified_identities.run LIKE :q", q: "%#{run}%") }
  scope :approved, -> { where(status: "approved") }
  scope :pending, -> { where(status: "pending") }
  scope :active, -> { where.not(status: "inactive") }

  def user
    requested_by || verified_identity&.users&.first
  end

  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
  def inactive? = status == "inactive"

  def deactivate!(reason:)
    self.deactivation_reason = reason
    self.status = "inactive"
    save!
  end
end
