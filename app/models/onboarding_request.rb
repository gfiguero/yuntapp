class OnboardingRequest < ApplicationRecord
  belongs_to :user
  belongs_to :neighborhood_association, optional: true
  belongs_to :region, optional: true
  belongs_to :commune, optional: true

  has_one :identity_verification_request, dependent: :destroy
  has_one :residence_verification_request, dependent: :destroy

  STATUSES = %w[draft pending approved rejected cancelled].freeze

  validates :status, inclusion: {in: STATUSES}
  validates :terms_accepted_at, presence: true, unless: -> { draft? || cancelled? }

  scope :draft, -> { where(status: "draft") }
  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :cancelled, -> { where(status: "cancelled") }

  def draft? = status == "draft"
  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
  def cancelled? = status == "cancelled"

  # Nombre legible del solicitante para los recordatorios al admin (BR-050).
  # Cae al email si aún no hay datos de identidad cargados.
  def applicant_name
    ivr = identity_verification_request
    full = [ivr&.first_name, ivr&.last_name].compact.join(" ").strip
    full.presence || user&.email
  end

  # Momento en que la solicitud entró a revisión (`pending`). Se usa para
  # informar la antigüedad en los recordatorios.
  def pending_since
    terms_accepted_at || created_at
  end

  def days_pending(as_of: Time.current)
    return 0 unless pending_since
    ((as_of - pending_since) / 1.day).floor
  end

  # BR-017: el envío de onboarding es atómico. OnboardingRequest +
  # IdentityVerificationRequest + ResidenceVerificationRequest pasan a
  # `pending` juntas. Si alguna update falla, se revierte todo y los
  # registros quedan en su estado original.
  def submit!(terms_accepted_at: Time.current)
    transaction do
      update!(status: "pending", terms_accepted_at: terms_accepted_at)
      identity_verification_request&.update!(status: "pending")
      residence_verification_request&.update!(status: "pending")
    end
    self
  end

  # BR-051: el usuario puede cancelar su solicitud `pending` en cualquier
  # momento. El cambio es atómico: OR + IVR + RVR pasan a `cancelled`,
  # preservando los datos para que el usuario pueda duplicarlos en una
  # nueva solicitud si lo desea (BR-048/BR-049).
  def cancel!
    raise "Only pending onboarding requests can be cancelled (current: #{status})" unless pending?
    transaction do
      update!(status: "cancelled")
      identity_verification_request&.update!(status: "cancelled")
      residence_verification_request&.update!(status: "cancelled")
    end
    self
  end
end
