module Filterable
  extend ActiveSupport::Concern

  included do
    scope :filter_by_id, ->(ids) { where(id: ids) }
    scope :filter_by_name, ->(name) { where.like(name: "%#{name}%") }
    scope :filter_by_status, ->(status) { where(status: status) }
    scope :filter_by_user_id, ->(user_id) { where(user_id: user_id) }
    scope :filter_by_run, ->(run) { where.like(run: "%#{run}%") }
    scope :filter_by_first_name, ->(name) { where.like(first_name: "%#{name}%") }
    scope :filter_by_last_name, ->(name) { where.like(last_name: "%#{name}%") }
    scope :filter_by_neighborhood_association_id, ->(id) { where(neighborhood_association_id: id) }
  end
end
