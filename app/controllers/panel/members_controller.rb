module Panel
  class MembersController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :ensure_household_admin!
    before_action :set_residency, only: [ :show, :edit, :update ]

    def index
      @residencies = current_user.household_unit.residencies.where.not(verified_identity: current_user.verified_identity)
    end

    def show
    end

    def new
      @residency = Residency.new
    end

    def create
      run = normalize_run(verified_identity_params[:run])
      verified_identity = VerifiedIdentity.find_or_initialize_by(run: run)
      verified_identity.assign_attributes(verified_identity_params.except(:run))
      verified_identity.run = run
      unless verified_identity.save
        @residency = Residency.new
        @residency.errors.merge!(verified_identity.errors)
        render :new, status: :unprocessable_content
        return
      end

      household_unit = current_user.household_unit
      @residency = Residency.new(documents: params.dig(:member, :documents))
      @residency.verified_identity = verified_identity
      @residency.household_unit = household_unit
      @residency.verified_residence = household_unit.verified_residence
      @residency.status = "pending"

      if @residency.save
        redirect_to panel_member_path(@residency), notice: I18n.t("panel.members.flash.requested")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      unless @residency.rejected?
        redirect_to panel_member_path(@residency)
      end
    end

    def update
      unless @residency.rejected?
        redirect_to panel_member_path(@residency)
        return
      end

      @residency.verified_identity.update!(verified_identity_params)
      @residency.status = "pending"

      if @residency.save
        redirect_to panel_member_path(@residency), notice: I18n.t("panel.members.flash.resubmitted")
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

    def set_residency
      @residency = current_user.household_unit.residencies.find(params[:id])
    end

    def normalize_run(value)
      cleaned = value.to_s.gsub(/[.\-\s]/, "").upcase
      if cleaned.match?(/\A\d{7,8}[0-9K]\z/)
        "#{cleaned[0..-2]}-#{cleaned[-1]}"
      else
        cleaned
      end
    end

    def verified_identity_params
      params.require(:member).permit(:first_name, :last_name, :run, :phone, :email)
    end
  end
end
