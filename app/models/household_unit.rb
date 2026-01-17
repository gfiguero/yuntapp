class HouseholdUnit < ApplicationRecord
  include Filterable

  belongs_to :neighborhood_delegation
  belongs_to :commune, optional: true
  has_many :members, dependent: :destroy

  validates :number, presence: true
end
