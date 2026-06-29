# Verificación pública del certificado de residencia. Sin autenticación.
# Cualquier persona (banco, arrendador, organismo) puede confirmar la autenticidad
# de un certificado emitido por Yuntapp ingresando el código alfanumérico o
# escaneando el QR del PDF.
#
# Reglas: BR-009, BR-078, BR-079, BR-080, BR-081.
class VerificationsController < ActionController::Base
  layout "verification"

  protect_from_forgery with: :exception
  skip_forgery_protection only: :lookup

  # GET /verify
  def index
  end

  # POST /verify
  # Recibe el código del formulario y redirige al show con el identifier.
  def lookup
    identifier = params[:identifier].to_s.strip
    if identifier.blank?
      redirect_to verify_path, alert: I18n.t("verifications.flash.missing_identifier")
      return
    end
    redirect_to verification_path(identifier: identifier)
  end

  # GET /verify/:identifier
  def show
    @certificate = ResidenceCertificate.find_for_public_verification(params[:identifier])

    if @certificate.nil?
      render :not_found, status: :not_found
    end
  end
end
