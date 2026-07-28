class Category < ApplicationRecord
  include Filterable

  # BR-100: borrar una categoría (taxonomía) no destruye las publicaciones de usuarios;
  # solo las desvincula (la categoría es opcional en Listing).
  has_many :listings, dependent: :nullify

  validates :name, presence: true
end
