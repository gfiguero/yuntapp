class CreatePaymentEvents < ActiveRecord::Migration[8.1]
  def change
    # #101/BR-071/BR-087: log histórico de cada evento de pago de MP e
    # idempotencia real. La clave de idempotencia es (payment_id, status) —NO
    # payment_id a secas—, para que un mismo pago con approved y luego
    # refunded/charged_back sean eventos distintos, ambos procesables (Batch G).
    create_table :payment_events do |t|
      t.string :payment_id, null: false
      t.string :status, null: false
      t.references :payable, polymorphic: true, null: false
      t.integer :amount
      t.datetime :processed_at, null: false

      t.timestamps
    end

    add_index :payment_events, [:payment_id, :status], unique: true
  end
end
