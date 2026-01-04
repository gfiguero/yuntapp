class Listing < ApplicationRecord
  include Filterable

  belongs_to :user
  
  validates :name, presence: true
end
