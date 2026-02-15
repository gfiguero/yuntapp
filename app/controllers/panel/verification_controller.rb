module Panel
  class VerificationController < ApplicationController
    layout "panel"
    before_action :authenticate_user!

    def show
      @persona = current_user.persona
      redirect_to new_panel_verification_path unless @persona
    end

    def new
      if current_user.persona&.verified?
        redirect_to panel_verification_path
        return
      end

      @persona = current_user.persona || Persona.new
    end

    def create
      if current_user.persona&.verified?
        redirect_to panel_verification_path
        return
      end

      run = normalize_run(params[:persona][:run])
      @persona = Persona.find_by(run: run)

      if @persona.present? && @persona.user.present? && @persona.user != current_user
        redirect_to new_panel_verification_path, alert: I18n.t("persona.message.run_already_claimed")
        return
      end

      @persona ||= Persona.new

      @persona.assign_attributes(verification_params)
      @persona.verification_status = "pending"

      if @persona.save
        @persona.identity_document.attach(params[:persona][:identity_document]) if params[:persona][:identity_document].present?
        current_user.update!(persona: @persona)
        redirect_to panel_verification_path, notice: I18n.t("persona.message.submitted")
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
      params.require(:persona).permit(:first_name, :last_name, :run, :phone)
    end
  end
end
