class ResidenceVerificationRequest < ApplicationRecord
  belongs_to :user
  belongs_to :neighborhood_association
  belongs_to :neighborhood_delegation
  belongs_to :commune
  belongs_to :onboarding_request, optional: true

  STATUSES = %w[pending approved rejected].freeze

  validates :number, :neighborhood_delegation_id, presence: true
  validates :status, inclusion: {in: STATUSES}

  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }

  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
end
