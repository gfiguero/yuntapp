class NeighborhoodAssociation < ApplicationRecord
  include Filterable

  validates :name, presence: true

  belongs_to :commune, optional: true
  has_many :neighborhood_delegations, dependent: :destroy
  has_many :household_units, through: :neighborhood_delegations
  has_many :members, through: :household_units
end
