class Member < ApplicationRecord
  include Filterable

  STATUSES = %w[pending approved rejected].freeze

  belongs_to :household_unit
  belongs_to :verified_identity

  # Relaciones para trazabilidad, pero el "Miembro" es la Identidad
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :board_members, dependent: :destroy
  has_many :residence_certificates, dependent: :destroy
  has_many_attached :documents

  validates :verified_identity_id, presence: true

  delegate :name, :run, :phone, :email, :first_name, :last_name, to: :verified_identity, allow_nil: true

  validates :status, presence: true, inclusion: {in: STATUSES}

  scope :filter_by_status, ->(status) { where(status: status) }
  scope :filter_by_name, ->(name) { joins(:verified_identity).where("verified_identities.first_name LIKE :q OR verified_identities.last_name LIKE :q", q: "%#{name}%") }
  scope :filter_by_run, ->(run) { joins(:verified_identity).where("verified_identities.run LIKE :q", q: "%#{run}%") }
  scope :approved, -> { where(status: "approved") }
  scope :pending, -> { where(status: "pending") }

  def user
    # Como Member es una identidad verificada, y esa identidad puede tener múltiples usuarios,
    # este método es ambiguo. Deberíamos evitar usarlo o definir qué usuario retorna.
    # Por ahora, retornamos el usuario que solicitó la membresía si existe,
    # o el primer usuario asociado a la identidad.
    requested_by || verified_identity&.users&.first
  end

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end
end
