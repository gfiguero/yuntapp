class AddManualAddressToResidenceVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :residence_verification_requests, :manual_address, :boolean, default: false, null: false
  end
end
