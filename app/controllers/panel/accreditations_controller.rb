module Panel
  class AccreditationsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :ensure_verified!, only: [:new, :create]
    before_action :ensure_household_unit!, only: [:show, :edit, :update]

    def show
      @member = current_user.member
      redirect_to new_panel_accreditation_path unless @member
    end

    def new
      if current_user.member
        redirect_to panel_accreditation_path
        return
      end

      @member = Member.new
    end

    def create
      if current_user.member
        redirect_to panel_accreditation_path
        return
      end

      household_unit = resolve_household_unit
      unless household_unit
        redirect_to new_panel_household_unit_path, alert: I18n.t("member.message.run_not_found_no_household")
        return
      end

      @member = Member.new(member_params)
      @member.persona = current_user.persona
      @member.requested_by = current_user
      @member.household_unit = household_unit
      @member.status = "pending"

      if @member.save
        session.delete(:pending_household_unit_id)
        redirect_to panel_accreditation_path, notice: I18n.t("member.message.requested")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @member = current_user.member
      unless @member&.rejected?
        redirect_to panel_accreditation_path
      end
    end

    def update
      @member = current_user.member
      unless @member&.rejected?
        redirect_to panel_accreditation_path
        return
      end

      @member.assign_attributes(member_params)
      @member.status = "pending"
      @member.rejection_reason = nil

      if @member.save
        redirect_to panel_accreditation_path, notice: I18n.t("member.message.resubmitted")
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def ensure_verified!
      unless current_user.verified?
        redirect_to new_panel_verification_path, alert: I18n.t("persona.message.must_verify_first")
      end
    end

    def ensure_household_unit!
      unless current_user.household_unit
        redirect_to new_panel_household_unit_path, alert: "Debes crear un domicilio primero."
      end
    end

    def resolve_household_unit
      current_user.household_unit || (session[:pending_household_unit_id] && HouseholdUnit.find_by(id: session[:pending_household_unit_id]))
    end

    def member_params
      params.require(:member).permit(documents: [])
    end
  end
end
