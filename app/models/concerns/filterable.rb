module Filterable
  extend ActiveSupport::Concern

  included do
    scope :filter_by_id, ->(ids) { where(id: ids) }
    scope :filter_by_name, ->(name) { where.like(name: "%#{name}%") }
  end
end
