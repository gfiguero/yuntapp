module Sortable
  extend ActiveSupport::Concern

  included do
    scope :sort_by_id, ->(direction = nil) { direction.present? ? reorder(id: direction) : reorder(id: :asc) }
    scope :sort_by_name, ->(direction = nil) { direction.present? ? reorder(name: direction) : reorder(name: :asc) }
    scope :sort_by_active, ->(direction = nil) { direction.present? ? reorder(active: direction) : reorder(active: :asc) }
    scope :sort_by_created_at, ->(direction = nil) { direction.present? ? reorder(created_at: direction) : reorder(created_at: :asc) }
    scope :sort_by_position, ->(direction = nil) { direction.present? ? reorder(position: direction) : reorder(position: :asc) }
    scope :sort_by_status, ->(direction = nil) { direction.present? ? reorder(status: direction) : reorder(status: :asc) }
    scope :sort_by_folio, ->(direction = nil) { direction.present? ? reorder(folio: direction) : reorder(folio: :asc) }
    scope :sort_by_member_id, ->(direction = nil) { direction.present? ? reorder(member_id: direction) : reorder(member_id: :asc) }
  end
end
