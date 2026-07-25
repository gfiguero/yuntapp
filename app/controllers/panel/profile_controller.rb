module Panel
  # Perfil del usuario: solo consulta. Los datos de identidad se corrigen con
  # un nuevo proceso de verificación (BR-046), el email es inmutable (BR-093)
  # y la contraseña se cambia en "Mi Cuenta" (Devise, exige contraseña actual
  # — BR-094).
  class ProfileController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :set_user

    def show
    end

    private

    def set_user
      @user = current_user
    end
  end
end
