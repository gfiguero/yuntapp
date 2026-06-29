module Admin
  class VerificationsController < Admin::ApplicationController
    before_action :set_verified_identity, only: [:show]

    def index
      @verified_identities = VerifiedIdentity
        .joins(:users)
        .where(users: {neighborhood_association_id: current_neighborhood_association.id})
        .order(created_at: :asc)
    end

    def show
    end

    private

    def set_verified_identity
      @verified_identity = VerifiedIdentity.joins(:users)
        .where(users: {neighborhood_association_id: current_neighborhood_association.id})
        .find(params[:id])
    end
  end
end
