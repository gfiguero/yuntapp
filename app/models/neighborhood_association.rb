class NeighborhoodAssociation < ApplicationRecord
  include Filterable

  validates :name, presence: true

  before_validation :normalize_rut

  # BR-119: RUT obligatorio, único y con DV válido (módulo 11). Reutiliza RunValidator.
  validates :rut, presence: true, uniqueness: true
  validates :rut, run: true, if: -> { rut.present? }

  belongs_to :commune, optional: true
  # BR-100/BR-055: la junta y su historial (delegaciones, domicilios, certificados,
  # precios, directiva) nunca se destruyen. La disolución es un cambio de estado.
  has_many :neighborhood_delegations, dependent: :restrict_with_error
  has_many :household_units, through: :neighborhood_delegations
  has_many :residencies, through: :household_units
  has_many :members
  has_many :users
  has_many :identity_verification_requests
  has_many :residence_verification_requests
  has_many :onboarding_requests
  has_many :board_members, dependent: :restrict_with_error
  has_many :residence_certificates, dependent: :restrict_with_error
  has_many :certificate_pricings, dependent: :restrict_with_error
  has_many :listing_pricings, dependent: :restrict_with_error

  scope :active, -> { where(active: true) }

  def inactive? = !active?

  def current_certificate_price
    CertificatePricing.current_for(self)&.price
  end

  def current_listing_price
    ListingPricing.current_for(self)&.price
  end

  # BR-054/BR-055: disolver una junta la marca inactive y pasa a inactive en cascada
  # a todos sus Member activos (con su propia cascada a dependientes, BR-099). No se
  # destruye nada: certificados, identidades y residencias se conservan como historial.
  def deactivate!
    transaction do
      update!(active: false)
      reason = I18n.t("superadmin.neighborhood_associations.dissolution_reason")
      members.active.pluck(:id).each do |member_id|
        member = Member.find(member_id)
        member.deactivate!(reason: reason) unless member.inactive?
      end
    end
  end

  private

  # Mismo patrón que VerifiedIdentity#normalize_run_field.
  def normalize_rut
    return unless rut.present?
    self.rut = rut.to_s.gsub(/[.\-\s]/, "").upcase
    self.rut = "#{rut[0..-2]}-#{rut[-1]}" if rut.match?(/\A\d{7,8}[0-9K]\z/)
  end
end
