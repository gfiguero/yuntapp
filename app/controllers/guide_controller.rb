# Guía pública que explica Yuntapp en un deck de diapositivas. Sin autenticación:
# cualquier persona puede entenderla, igual que la verificación de certificados.
class GuideController < ApplicationController
  skip_before_action :authenticate_user!
  layout "guide"

  def index
  end
end
