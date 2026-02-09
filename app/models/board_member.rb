class BoardMember < ApplicationRecord
  include Filterable

  POSITIONS = %w[presidente secretario tesorero director].freeze

  belongs_to :neighborhood_association
  belongs_to :member

  validates :position, presence: true, inclusion: {in: POSITIONS}
  validates :start_date, presence: true

  scope :active, -> { where(active: true) }
  scope :filter_by_position, ->(position) { where(position: position) }
  scope :filter_by_active, ->(active) { where(active: active) }
end
