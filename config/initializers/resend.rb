# Configuracion de Resend para el envio de correo transaccional.
# La API key se toma de ENV["RESEND_API_KEY"] o de las credenciales cifradas
# (bin/rails credentials:edit -> resend: api_key). Mismo patron que MercadoPago.
# En development/test queda nil y no se usa (solo produccion usa delivery_method :resend).
Resend.api_key = ENV["RESEND_API_KEY"] || Rails.application.credentials.dig(:resend, :api_key)
