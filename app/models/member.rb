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
  validates :status, presence: true, inclusion: {in: STATUSES}
  validates :deactivation_reason, presence: true, if: -> { inactive? }

  delegate :name, :run, :phone, :email, :first_name, :last_name, to: :verified_identity, allow_nil: true

  scope :filter_by_status, ->(status) { where(status: status) }
  scope :filter_by_name, ->(name) { joins(:verified_identity).where("verified_identities.first_name LIKE :q OR verified_identities.last_name LIKE :q", q: "%#{name}%") }
  scope :filter_by_run, ->(run) { joins(:verified_identity).where("verified_identities.run LIKE :q", q: "%#{run}%") }
  scope :approved, -> { where(status: "approved") }
  scope :pending, -> { where(status: "pending") }
  scope :active, -> { where.not(status: "inactive") }
  scope :dependent, -> { where(dependent: true) }
  scope :independent, -> { where(dependent: false) }

  def user
    requested_by || verified_identity&.users&.first
  end

  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
  def inactive? = status == "inactive"
  def dependent? = dependent

  # Residencia aprobada más reciente del socio (mismo criterio que User#residency).
  def residency
    verified_identity&.residencies&.approved&.order(created_at: :desc)&.first
  end

  def household_admin?
    residency&.household_admin? || false
  end

  # Residentes dependientes del mismo grupo familiar que este socio gestiona.
  def dependent_members
    family_group = residency&.family_group
    return Member.none unless family_group

    Member.dependent.active
      .joins(:verified_identity)
      .joins("INNER JOIN residencies ON residencies.verified_identity_id = verified_identities.id")
      .where(residencies: {family_group_id: family_group.id, status: "approved"})
      .where(neighborhood_association_id: neighborhood_association_id)
      .distinct
  end

  # BR-037/BR-038: al desactivar un household_admin, sus residentes dependientes
  # quedan desactivados en cascada conservando registro y motivo. La operación es
  # atómica: si algo falla, no queda nadie a medio desactivar.
  def deactivate!(reason:)
    transaction do
      mark_inactive!(reason)

      if household_admin?
        cascade_reason = I18n.t("members.deactivation.cascade_reason", reason: reason)
        dependent_members.find_each { |dependent| dependent.mark_inactive!(cascade_reason) }
      end
    end
  end

  protected

  def mark_inactive!(reason)
    update!(status: "inactive", deactivation_reason: reason)
  end
end
