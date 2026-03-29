module Superadmin
  class DashboardController < ApplicationController
    def index
      @stats = {
        neighborhood_associations: NeighborhoodAssociation.count,
        onboarding_pending: OnboardingRequest.where(status: "pending").count,
        identity_pending: IdentityVerificationRequest.where(status: "pending").count,
        residence_pending: ResidenceVerificationRequest.where(status: "pending").count,
        users_total: User.count
      }
    end
  end
end
