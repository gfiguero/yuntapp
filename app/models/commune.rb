class Commune < ApplicationRecord
  belongs_to :region
  has_many :neighborhood_associations
  has_many :household_units
  scope :sort_by_region_name, ->(direction = nil) {
    joins(:region).reorder("regions.name #{sanitize_sql_for_order(direction.presence || :asc)}")
  }

  validates :name, presence: true
end
