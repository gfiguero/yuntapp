class RemoveUnusedFieldsFromResidenceVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    remove_column :residence_verification_requests, :city, :string
    remove_column :residence_verification_requests, :region, :string
    remove_column :residence_verification_requests, :country, :string
    remove_column :residence_verification_requests, :postal_code, :string
  end
end
