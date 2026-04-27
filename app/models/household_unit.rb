class HouseholdUnit < ApplicationRecord
  include Filterable

  belongs_to :neighborhood_delegation
  belongs_to :commune, optional: true
  belongs_to :verified_residence, optional: true
  has_many :family_groups, dependent: :destroy
  has_many :residencies, dependent: :destroy
  has_many :approved_residencies, -> { where(status: "approved") }, class_name: "Residency"

  validates :number, presence: true

  scope :filter_by_number, ->(number) { where.like(number: "%#{number}%") }
  scope :filter_by_neighborhood_delegation_id, ->(id) { where(neighborhood_delegation_id: id) }

  def household_admin
    residencies.find_by(household_admin: true)
  end
end
