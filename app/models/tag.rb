class Tag < ApplicationRecord
  include Filterable

  validates :name, presence: true
end
