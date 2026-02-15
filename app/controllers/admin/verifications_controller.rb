module Admin
  class VerificationsController < Admin::ApplicationController
    before_action :set_persona, only: [:show, :approve, :reject]

    def index
      @personas = Persona.pending
        .joins(:user)
        .where(users: {neighborhood_association_id: current_neighborhood_association.id})
        .order(created_at: :asc)
    end

    def show
    end

    def approve
      @persona.update!(verification_status: "verified")
      redirect_to admin_verification_path(@persona), notice: I18n.t("persona.message.approved"), status: :see_other
    end

    def reject
      @persona.update!(verification_status: "rejected")
      redirect_to admin_verification_path(@persona), notice: I18n.t("persona.message.rejected"), status: :see_other
    end

    private

    def set_persona
      @persona = Persona.joins(:user)
        .where(users: {neighborhood_association_id: current_neighborhood_association.id})
        .find(params[:id])
    end
  end
end
