class AddPaymentFieldsToResidenceCertificates < ActiveRecord::Migration[8.1]
  def change
    change_table :residence_certificates do |t|
      t.integer :amount
      t.integer :platform_fee
      t.string :payment_id
      t.datetime :paid_at
    end

    add_index :residence_certificates, :payment_id, unique: true, where: "payment_id IS NOT NULL"
  end
end
