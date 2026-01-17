class Member < ApplicationRecord
  include Filterable

  belongs_to :household_unit

  validates :first_name, :last_name, :run, presence: true
end
