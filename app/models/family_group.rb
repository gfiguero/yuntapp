class FamilyGroup < ApplicationRecord
  belongs_to :household_unit

  has_many :residencies, dependent: :nullify

  def household_admin
    residencies.approved.find_by(household_admin: true)
  end
end
