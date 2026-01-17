class Country < ApplicationRecord
  include Filterable

  has_many :regions, dependent: :destroy

  validates :name, presence: true
end
