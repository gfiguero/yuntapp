class Region < ApplicationRecord
  belongs_to :country
  has_many :communes, dependent: :destroy

  scope :sort_by_country_name, ->(direction = nil) {
    joins(:country).reorder("countries.name #{sanitize_sql_for_order(direction.presence || :asc)}")
  }

  validates :name, presence: true
end
