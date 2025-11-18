module Filterable
  extend ActiveSupport::Concern

  included do
    scope :filter_by_id, ->(id) { where(id: id) }
    scope :filter_by_name, ->(name) { where.like(name: "%#{name}%") }
  end
end
