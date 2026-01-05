class ApplicationRecord < ActiveRecord::Base
  include Sortable
  include Filterable

  primary_abstract_class
end
