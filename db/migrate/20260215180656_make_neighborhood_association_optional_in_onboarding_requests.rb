class MakeNeighborhoodAssociationOptionalInOnboardingRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_null :onboarding_requests, :neighborhood_association_id, true
  end
end
