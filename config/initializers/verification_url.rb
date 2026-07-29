# Host base para las URLs y QR de verificación pública de certificados (UC-007).
# El PDF es inmutable (BR-075): un host equivocado deja los QR apuntando al
# dominio erróneo para siempre, por eso lo resolvemos explícitamente y lo
# validamos en producción (#102).
#
# Prioridad: ENV["YUNTAPP_HOST"] → credentials.verification_base_url → default.
# `YUNTAPP_HOST` es solo el host (ej. "yuntapp.cl"); credentials/config pueden
# traer la URL base completa (ej. "https://yuntapp.cl").
base_url =
  if ENV["YUNTAPP_HOST"].present?
    "https://#{ENV["YUNTAPP_HOST"]}"
  else
    Rails.application.credentials.verification_base_url.presence || "https://yuntapp.cl"
  end

Rails.application.config.x.verification_base_url = base_url

# En producción, exigir que el host esté configurado explícitamente (ENV o
# credentials) en vez de caer al default silencioso, que emitiría QR al dominio
# equivocado en cualquier despliegue que no sea yuntapp.cl.
if Rails.env.production? &&
    ENV["YUNTAPP_HOST"].blank? &&
    Rails.application.credentials.verification_base_url.blank?
  Rails.logger.warn(
    "[verification_url] YUNTAPP_HOST no está configurado en producción; " \
    "los QR de certificados usarán el default #{base_url}. " \
    "Definí YUNTAPP_HOST en config/deploy.yml (env.clear)."
  )
end
