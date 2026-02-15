module Panel
  class ProfileController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :set_user

    def show
    end

    def update
      # Si el campo password está vacío, lo removemos para evitar errores de validación
      # y permitir actualizar otros datos sin cambiar la clave.
      if params[:user][:password].blank?
        params[:user].delete(:password)
        params[:user].delete(:password_confirmation)
      end

      if @user.update(user_params)
        # Sign in the user by passing validation in case their password changed
        bypass_sign_in(@user)
        redirect_to panel_profile_path, notice: "Perfil actualizado exitosamente."
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    def set_user
      @user = current_user
    end

    def user_params
      params.require(:user).permit(:email, :password, :password_confirmation)
    end
  end
end
