class Country < ApplicationRecord
  include Filterable

  # BR-100: la geografía es dato de referencia del que cuelgan juntas, domicilios
  # y todo el historial. Con `dependent: :destroy` borrar un país cascadeaba
  # región→comuna y rompía/orfanaba las juntas de esas comunas.
  has_many :regions, dependent: :restrict_with_error

  validates :name, presence: true
end
