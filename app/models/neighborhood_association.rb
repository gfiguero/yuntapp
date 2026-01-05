class NeighborhoodAssociation < ApplicationRecord
  include Filterable

  validates :name, presence: true
end
