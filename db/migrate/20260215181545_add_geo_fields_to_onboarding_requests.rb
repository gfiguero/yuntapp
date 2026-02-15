class AddGeoFieldsToOnboardingRequests < ActiveRecord::Migration[8.1]
  def change
    add_reference :onboarding_requests, :region, null: true, foreign_key: true
    add_reference :onboarding_requests, :commune, null: true, foreign_key: true
  end
end
