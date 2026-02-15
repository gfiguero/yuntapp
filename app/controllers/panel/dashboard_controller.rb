module Panel
  class DashboardController < ApplicationController
    before_action :authenticate_user!
    before_action :redirect_to_onboarding!, only: :index
    layout "panel"

    def index
    end

    private

    def redirect_to_onboarding!
      redirect_to panel_onboarding_step1_path if current_user.member.nil?
    end
  end
end
