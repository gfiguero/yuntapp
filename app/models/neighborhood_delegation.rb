class NeighborhoodDelegation < ApplicationRecord
  include Filterable

  belongs_to :neighborhood_association
  # BR-100: las delegaciones y sus domicilios no se destruyen.
  has_many :household_units, dependent: :restrict_with_error

  validates :name, presence: true
end
