class ChangeDefaultStatusToDraftInOnboardingRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_default :onboarding_requests, :status, from: "pending", to: "draft"
  end
end
