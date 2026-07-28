class ResidenceVerificationRequest < ApplicationRecord
  belongs_to :user
  belongs_to :neighborhood_association
  belongs_to :neighborhood_delegation, optional: true
  belongs_to :commune
  belongs_to :onboarding_request, optional: true

  has_many_attached :residence_documents

  STATUSES = %w[draft pending approved rejected cancelled].freeze

  # BR-019/BR-020: el domicilio exige `number` siempre y delegación O calle.
  # Se valida desde `pending` en adelante: en `draft` el onboarding persiste
  # datos parciales vía autosave (mismo patrón que IdentityVerificationRequest).
  # NO usar `allow_blank: true` junto a `presence: true` — se anulan entre sí.
  validates :number, presence: true, unless: -> { draft? }
  validates :neighborhood_delegation_id, presence: true, if: -> { !draft? && street_name.blank? }
  validates :street_name, presence: true, if: -> { !draft? && neighborhood_delegation_id.blank? }
  validates :status, inclusion: {in: STATUSES}

  scope :draft, -> { where(status: "draft") }
  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }

  def draft? = status == "draft"
  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
end
