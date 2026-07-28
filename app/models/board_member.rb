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

  def active? = active

  # BR-100: la directiva es historial institucional. La "baja" de un cargo no destruye
  # el registro: lo cierra (active: false + end_date). El historial de cargos se conserva.
  def end_term!(on: Date.current)
    update!(active: false, end_date: on)
  end
end
