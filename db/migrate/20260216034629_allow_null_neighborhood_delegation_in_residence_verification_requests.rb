class AllowNullNeighborhoodDelegationInResidenceVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_null :residence_verification_requests, :neighborhood_delegation_id, true
  end
end
