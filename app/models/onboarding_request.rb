class OnboardingRequest < ApplicationRecord
  belongs_to :user
  belongs_to :neighborhood_association, optional: true
  belongs_to :region, optional: true
  belongs_to :commune, optional: true

  has_one :identity_verification_request, dependent: :destroy
  has_one :residence_verification_request, dependent: :destroy

  STATUSES = %w[draft pending approved rejected cancelled].freeze

  class NotDuplicableError < StandardError; end

  validates :status, inclusion: {in: STATUSES}
  validates :terms_accepted_at, presence: true, unless: -> { draft? || cancelled? }
  # BR-047/BR-060 (#105): el rechazo debe registrar el motivo (visible en el
  # historial, obligatorio ante posible fraude por RUN duplicado).
  validates :rejection_reason, presence: true, if: -> { rejected? }

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

  # BR-048/BR-049: el usuario puede duplicar una solicitud resuelta para
  # corregir solo lo necesario en vez de empezar de cero. La copia nace en
  # `draft` y la original queda intacta en el historial (BR-047).
  #
  # Los documentos adjuntos NO se copian, por decisión de producto: el rechazo
  # suele deberse justamente a un documento ilegible o incorrecto, y recopiarlo
  # invitaría a reenviar el mismo problema.
  DUPLICABLE_STATUSES = %w[rejected cancelled].freeze

  def duplicable? = DUPLICABLE_STATUSES.include?(status)

  def duplicate!
    raise NotDuplicableError, "Cannot duplicate an onboarding request in status: #{status}" unless duplicable?

    transaction do
      copy = OnboardingRequest.create!(
        user: user,
        status: "draft",
        neighborhood_association: neighborhood_association,
        region: region,
        commune: commune
      )
      duplicate_identity_request_into(copy)
      duplicate_residence_request_into(copy)
      copy
    end
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

  private

  # Copia los datos de texto de la identidad. Sin documentos (ver `duplicate!`),
  # sin estado heredado y sin el motivo de rechazo de la solicitud anterior.
  def duplicate_identity_request_into(copy)
    source = identity_verification_request
    return if source.nil?

    IdentityVerificationRequest.create!(
      user: source.user,
      onboarding_request: copy,
      neighborhood_association: source.neighborhood_association,
      first_name: source.first_name,
      last_name: source.last_name,
      run: source.run,
      phone: source.phone,
      status: "draft"
    )
  end

  def duplicate_residence_request_into(copy)
    source = residence_verification_request
    return if source.nil?

    ResidenceVerificationRequest.create!(
      user: source.user,
      onboarding_request: copy,
      neighborhood_association: source.neighborhood_association,
      commune_id: source.commune_id,
      neighborhood_delegation_id: source.neighborhood_delegation_id,
      street_name: source.street_name,
      number: source.number,
      address_detail: source.address_detail,
      manual_address: source.manual_address,
      status: "draft"
    )
  end
end
