class AddIdentityVerificationRequestToVerifiedIdentities < ActiveRecord::Migration[8.1]
  def change
    add_reference :verified_identities, :identity_verification_request, null: true, foreign_key: true
  end
end
