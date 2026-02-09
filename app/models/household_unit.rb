class HouseholdUnit < ApplicationRecord
  include Filterable

  belongs_to :neighborhood_delegation
  belongs_to :commune, optional: true
  has_many :members, dependent: :destroy
  has_many :approved_members, -> { where(status: "approved") }, class_name: "Member"

  validates :number, presence: true

  def household_admin
    members.find_by(household_admin: true)
  end
end
