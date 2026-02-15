module Panel
  class MembersController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :ensure_household_admin!
    before_action :set_member, only: [:show, :edit, :update]

    def index
      @members = current_user.household_unit.members.where.not(id: current_user.member&.id)
    end

    def show
    end

    def new
      @member = Member.new
    end

    def create
      run = normalize_run(persona_params[:run])
      persona = Persona.find_or_initialize_by(run: run)
      persona.assign_attributes(persona_params.except(:run))
      persona.run = run
      persona.verification_status ||= "pending"

      unless persona.save
        @member = Member.new
        @member.errors.merge!(persona.errors)
        render :new, status: :unprocessable_content
        return
      end

      @member = Member.new(documents: params.dig(:member, :documents))
      @member.persona = persona
      @member.household_unit = current_user.household_unit
      @member.requested_by = current_user
      @member.status = "pending"

      if @member.save
        redirect_to panel_member_path(@member), notice: I18n.t("member.message.requested")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      unless @member.rejected?
        redirect_to panel_member_path(@member)
      end
    end

    def update
      unless @member.rejected?
        redirect_to panel_member_path(@member)
        return
      end

      @member.persona.update!(persona_params)
      @member.status = "pending"
      @member.rejection_reason = nil

      if @member.save
        redirect_to panel_member_path(@member), notice: I18n.t("member.message.resubmitted")
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def ensure_household_admin!
      unless current_user.household_admin?
        redirect_to panel_root_path, alert: "Debes ser administrador del domicilio para gestionar socios."
      end
    end

    def set_member
      @member = current_user.household_unit.members.find(params[:id])
    end

    def normalize_run(value)
      cleaned = value.to_s.gsub(/[.\-\s]/, "").upcase
      if cleaned.match?(/\A\d{7,8}[0-9K]\z/)
        "#{cleaned[0..-2]}-#{cleaned[-1]}"
      else
        cleaned
      end
    end

    def persona_params
      params.require(:member).permit(:first_name, :last_name, :run, :phone, :email)
    end
  end
end
