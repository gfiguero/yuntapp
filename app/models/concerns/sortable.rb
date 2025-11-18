module Sortable
  extend ActiveSupport::Concern

  included do
    scope :sort_by_id, ->(direction = nil) { direction.present? ? reorder(id: direction) : reorder(id: :asc) }
    scope :sort_by_name, ->(direction = nil) { direction.present? ? reorder(name: direction) : reorder(name: :asc) }
    scope :sort_by_created_at, ->(direction = nil) { direction.present? ? reorder(created_at: direction) : reorder(created_at: :asc) }
  end
end
