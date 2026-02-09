module Panel
  class AccreditationsController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
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

      run = normalize_run(member_params[:run])
      existing_member = Member.approved.where(user_id: nil).find_by(run: run)

      if existing_member
        existing_member.update!(user: current_user)
        current_user.update!(household_unit: existing_member.household_unit)
        redirect_to panel_accreditation_path, notice: I18n.t("member.message.linked")
      else
        unless current_user.household_unit
          redirect_to new_panel_household_unit_path, alert: I18n.t("member.message.run_not_found_no_household")
          return
        end

        @member = Member.new(member_params)
        @member.user = current_user
        @member.requested_by = current_user
        @member.household_unit = current_user.household_unit
        @member.status = "pending"

        if @member.save
          redirect_to panel_accreditation_path, notice: I18n.t("member.message.requested")
        else
          render :new, status: :unprocessable_content
        end
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

    def ensure_household_unit!
      unless current_user.household_unit
        redirect_to new_panel_household_unit_path, alert: "Debes crear un domicilio primero."
      end
    end

    def normalize_run(value)
      value.to_s.gsub(/[.\-\s]/, "").upcase
    end

    def member_params
      params.require(:member).permit(:first_name, :last_name, :run, :phone, documents: [])
    end
  end
end
