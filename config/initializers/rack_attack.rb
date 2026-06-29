require "rack/attack"

# Rate limiting para el endpoint público de verificación de certificados (UC-007).
# El validation_code es de 8 chars alfanumérico (~33^8 ≈ 1.4T combinaciones), brute-force
# es teóricamente posible. Limitamos a 10 requests/minuto por IP para mitigar.
#
# Aplicado solo a /verify (GET) y /verify/:identifier (GET). El POST de lookup
# redirige al GET, así que el throttle aplica naturalmente al subsiguiente.

# Usar un store en memoria propio para evitar depender de Rails.cache (que en
# test es NullStore y en producción podría ser compartido con otros usos).
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

# 10 requests por minuto por IP a cualquier path bajo /verify
Rack::Attack.throttle("verify/ip", limit: 10, period: 60.seconds) do |req|
  req.ip if req.path.start_with?("/verify")
end

# Respuesta cuando se excede el límite: 429 Too Many Requests + Retry-After
Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"] || {}
  retry_after = match_data[:period] || 60
  [
    429,
    {
      "Content-Type" => "text/plain",
      "Retry-After" => retry_after.to_s
    },
    ["Demasiadas verificaciones desde tu IP. Intenta nuevamente en #{retry_after} segundos.\n"]
  ]
end
