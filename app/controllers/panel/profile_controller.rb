module Panel
  class ProfileController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :set_user

    def show
    end

    def edit
    end

    def update
      if @user.update(user_params)
        redirect_to panel_profile_path, notice: "Perfil actualizado exitosamente."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_user
      @user = current_user
    end

    def user_params
      params.require(:user).permit(:first_name, :last_name, :email, :password, :password_confirmation)
    end
  end
end
