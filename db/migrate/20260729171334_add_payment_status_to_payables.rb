class AddPaymentStatusToPayables < ActiveRecord::Migration[8.1]
  def change
    # #125/#127: estado crudo del último pago reportado por MP (approved,
    # in_process, pending, rejected, cancelled, refunded, charged_back).
    # No cambia el enum de negocio status/publication_status (BR-064).
    add_column :residence_certificates, :payment_status, :string
    add_column :listings, :payment_status, :string
  end
end
