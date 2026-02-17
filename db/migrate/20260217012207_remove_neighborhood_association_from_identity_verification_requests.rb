class RemoveNeighborhoodAssociationFromIdentityVerificationRequests < ActiveRecord::Migration[8.1]
  def change
    remove_reference :identity_verification_requests, :neighborhood_association, null: false, foreign_key: true
  end
end
