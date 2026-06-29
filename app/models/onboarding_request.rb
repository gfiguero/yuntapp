class OnboardingRequest < ApplicationRecord
  belongs_to :user
  belongs_to :neighborhood_association, optional: true
  belongs_to :region, optional: true
  belongs_to :commune, optional: true

  has_one :identity_verification_request, dependent: :destroy
  has_one :residence_verification_request, dependent: :destroy

  STATUSES = %w[draft pending approved rejected].freeze

  validates :status, inclusion: {in: STATUSES}
  validates :terms_accepted_at, presence: true, unless: :draft?

  scope :draft, -> { where(status: "draft") }
  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }

  def draft? = status == "draft"
  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
end
