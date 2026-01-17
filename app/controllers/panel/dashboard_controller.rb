module Panel
  class DashboardController < ApplicationController
    before_action :authenticate_user!
    layout "panel"

    def index
    end
  end
end
