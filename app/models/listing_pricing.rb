# Precio histórico por junta para habilitar publicaciones del marketplace
# (BR-084). Mismo esquema de vigencias que CertificatePricing (BR-070):
# crear un precio nuevo cierra automáticamente la vigencia del anterior.
class ListingPricing < ApplicationRecord
  MINIMUM_PRICE = 1000

  belongs_to :neighborhood_association
  belongs_to :created_by, class_name: "User"

  validates :price, numericality: {only_integer: true, greater_than_or_equal_to: MINIMUM_PRICE}
  validates :effective_from, presence: true

  before_create :close_previous_pricing!

  scope :active, -> { where(effective_to: nil) }

  def self.current_for(neighborhood_association)
    where(neighborhood_association: neighborhood_association)
      .active
      .order(effective_from: :desc)
      .first
  end

  def active?
    effective_to.nil?
  end

  private

  def close_previous_pricing!
    self.class
      .where(neighborhood_association: neighborhood_association)
      .active
      .update_all(effective_to: Time.current, updated_at: Time.current)
  end
end
