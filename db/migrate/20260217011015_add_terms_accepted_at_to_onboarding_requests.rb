class AddTermsAcceptedAtToOnboardingRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :onboarding_requests, :terms_accepted_at, :datetime
  end
end
