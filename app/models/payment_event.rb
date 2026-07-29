class PaymentEvent < ApplicationRecord
  # #101/BR-071/BR-087: registro histórico e idempotente de cada evento de pago
  # de MercadoPago. La idempotencia es por (payment_id, status): un mismo pago
  # con `approved` y luego `refunded`/`charged_back` son eventos distintos.
  belongs_to :payable, polymorphic: true

  validates :payment_id, presence: true, uniqueness: {scope: :status}
  validates :status, presence: true
  validates :processed_at, presence: true
end
