class Listing < ApplicationRecord
  include Filterable

  belongs_to :user
  belongs_to :category, optional: true
  
  validates :name, presence: true
end
