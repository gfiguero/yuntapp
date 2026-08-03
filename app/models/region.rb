class Region < ApplicationRecord
  belongs_to :country
  # BR-100: ver Country#regions — no se borra geografía con dependientes.
  has_many :communes, dependent: :restrict_with_error

  scope :sort_by_country_name, ->(direction = nil) {
    joins(:country).reorder("countries.name #{sanitize_sql_for_order(direction.presence || :asc)}")
  }

  validates :name, presence: true
end
