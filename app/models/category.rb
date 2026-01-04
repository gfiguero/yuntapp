class Category < ApplicationRecord
  include Filterable

  validates :name, presence: true
end
