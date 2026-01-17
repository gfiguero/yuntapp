class NeighborhoodDelegation < ApplicationRecord
  include Filterable

  belongs_to :neighborhood_association
  has_many :household_units, dependent: :destroy

  validates :name, presence: true
end
