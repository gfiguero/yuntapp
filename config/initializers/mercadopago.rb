Rails.application.config.mercadopago = {
  access_token: ENV["MERCADOPAGO_ACCESS_TOKEN"] || Rails.application.credentials.dig(:mercadopago, :access_token),
  webhook_secret: ENV["MERCADOPAGO_WEBHOOK_SECRET"] || Rails.application.credentials.dig(:mercadopago, :webhook_secret)
}
