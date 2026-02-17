module Panel
  class VerificationController < ApplicationController
    layout "panel"
    before_action :authenticate_user!

    def show
      @verified_identity = current_user.verified_identity
      redirect_to new_panel_verification_path unless @verified_identity
    end

    def new
      if current_user.verified_identity&.verified?
        redirect_to panel_verification_path
        return
      end

      @verified_identity = current_user.verified_identity || VerifiedIdentity.new
    end

    def create
      if current_user.verified_identity&.verified?
        redirect_to panel_verification_path
        return
      end

      run = normalize_run(params[:verified_identity][:run])
      @verified_identity = VerifiedIdentity.find_by(run: run)

      if @verified_identity.present? && @verified_identity.users.any? && @verified_identity.users.exclude?(current_user)
        redirect_to new_panel_verification_path, alert: I18n.t("panel.verification.flash.run_already_claimed")
        return
      end

      @verified_identity ||= VerifiedIdentity.new

      @verified_identity.assign_attributes(verification_params)
      @verified_identity.verification_status = "pending"

      if @verified_identity.save
        @verified_identity.identity_document.attach(params[:verified_identity][:identity_document]) if params[:verified_identity][:identity_document].present?
        current_user.update!(verified_identity: @verified_identity)
        redirect_to panel_verification_path, notice: I18n.t("panel.verification.flash.submitted")
      else
        render :new, status: :unprocessable_content
      end
    end

    private

    def normalize_run(value)
      cleaned = value.to_s.gsub(/[.\-\s]/, "").upcase
      if cleaned.match?(/\A\d{7,8}[0-9K]\z/)
        "#{cleaned[0..-2]}-#{cleaned[-1]}"
      else
        cleaned
      end
    end

    def verification_params
      params.require(:verified_identity).permit(:first_name, :last_name, :run, :phone)
    end
  end
end
