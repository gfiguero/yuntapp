class BoardMember < ApplicationRecord
  include Filterable

  POSITIONS = %w[presidente secretario tesorero director].freeze

  belongs_to :neighborhood_association
  belongs_to :member

  validates :position, presence: true, inclusion: {in: POSITIONS}
  validates :start_date, presence: true

  # BR-007: la directiva de una junta solo puede componerse de socios de esa
  # misma junta. El <select> del formulario ya está acotado, pero es defensa de
  # cliente: `member_id` viaja por strong params, así que un POST manipulado
  # colaba un Member ajeno y filtraba su identidad (nombre y RUN) en las vistas
  # de directiva —incluida la pública de la junta—. El corte va en el modelo
  # para cubrir cualquier ruta de escritura, no solo el controller.
  validate :member_belongs_to_association

  scope :active, -> { where(active: true) }
  scope :filter_by_position, ->(position) { where(position: position) }
  scope :filter_by_active, ->(active) { where(active: active) }

  def active? = active

  # BR-100: la directiva es historial institucional. La "baja" de un cargo no destruye
  # el registro: lo cierra (active: false + end_date). El historial de cargos se conserva.
  def end_term!(on: Date.current)
    update!(active: false, end_date: on)
  end

  private

  def member_belongs_to_association
    return if member.nil? || neighborhood_association_id.nil?
    return if member.neighborhood_association_id == neighborhood_association_id

    errors.add(:member, :not_in_association)
  end
end
