class HouseholdUnit < ApplicationRecord
  include Filterable

  belongs_to :neighborhood_delegation
  belongs_to :commune, optional: true
  # BR-100/BR-030: los domicilios y su historial de residencia no se destruyen.
  has_many :family_groups, dependent: :restrict_with_error
  has_many :residencies, dependent: :restrict_with_error
  has_many :approved_residencies, -> { where(status: "approved") }, class_name: "Residency"

  validates :number, presence: true

  scope :filter_by_number, ->(number) { where.like(number: "%#{number}%") }
  scope :filter_by_neighborhood_delegation_id, ->(id) { where(neighborhood_delegation_id: id) }

  def household_admin
    residencies.find_by(household_admin: true)
  end

  # #97: "residente actual" = última estancia aprobada por identidad. Con el
  # historial de estancias (varias Residency por identidad+domicilio), deduplica
  # a una fila por persona. El corte de acceso real sigue siendo Member (BR-091).
  def current_residencies
    approved_residencies
      .group_by(&:verified_identity_id)
      .values
      .map { |stays| stays.max_by(&:created_at) }
  end
end
