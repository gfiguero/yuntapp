class Residency < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :verified_identity
  belongs_to :verified_residence
  belongs_to :household_unit
  belongs_to :family_group, optional: true

  has_many_attached :documents

  validates :verified_identity_id, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :approved, -> { where(status: "approved") }

  delegate :name, :run, :phone, :email, :first_name, :last_name, to: :verified_identity, allow_nil: true

  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
  def household_admin? = household_admin
end
