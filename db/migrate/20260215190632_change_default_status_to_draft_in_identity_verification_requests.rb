class ChangeDefaultStatusToDraftInIdentityVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_default :identity_verification_requests, :status, from: "pending", to: "draft"
  end
end
