class AddIssuanceFieldsToResidenceCertificates < ActiveRecord::Migration[8.1]
  def change
    change_table :residence_certificates do |t|
      t.string :validation_token
      t.string :validation_code
      t.datetime :issued_at
    end

    add_index :residence_certificates, :validation_token, unique: true, where: "validation_token IS NOT NULL"
    add_index :residence_certificates, :validation_code, unique: true, where: "validation_code IS NOT NULL"
  end
end
