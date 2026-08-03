class Commune < ApplicationRecord
  belongs_to :region
  # BR-100: sin `dependent` estas asociaciones dejaban borrar la comuna y orfanar
  # juntas y domicilios (nullify por defecto en la FK).
  has_many :neighborhood_associations, dependent: :restrict_with_error
  has_many :household_units, dependent: :restrict_with_error
  scope :sort_by_region_name, ->(direction = nil) {
    joins(:region).reorder("regions.name #{sanitize_sql_for_order(direction.presence || :asc)}")
  }

  validates :name, presence: true
end
