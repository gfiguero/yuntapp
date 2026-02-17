module Admin
  class VerificationsController < Admin::ApplicationController
    before_action :set_verified_identity, only: [:show, :approve, :reject]

    def index
      @verified_identities = VerifiedIdentity.pending
        .joins(:users)
        .where(users: {neighborhood_association_id: current_neighborhood_association.id})
        .order(created_at: :asc)
    end

    def show
    end

    def approve
      @verified_identity.update!(verification_status: "verified")
      redirect_to admin_verification_path(@verified_identity), notice: I18n.t("admin.verifications.flash.approved"), status: :see_other
    end

    def reject
      @verified_identity.update!(verification_status: "rejected")
      redirect_to admin_verification_path(@verified_identity), notice: I18n.t("admin.verifications.flash.rejected"), status: :see_other
    end

    private

    def set_verified_identity
      @verified_identity = VerifiedIdentity.joins(:users)
        .where(users: {neighborhood_association_id: current_neighborhood_association.id})
        .find(params[:id])
    end
  end
end
