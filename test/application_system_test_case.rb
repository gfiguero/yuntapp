require "test_helper"

# Dos modos de ejecución, misma suite:
#
#   1. Local (por defecto) — Chrome del host, arranque rápido, para el ciclo de
#      desarrollo. No prueba los assets precompilados.
#
#   2. Contenedor (SELENIUM_REMOTE_URL presente) — la app corre sobre la imagen
#      de producción tal cual y el navegador vive en un contenedor aparte
#      (`selenium/standalone-chromium`). Es el único modo con production parity:
#      verificado que `asset_path("application.js")` devuelve el mismo digest
#      precompilado que en RAILS_ENV=production, así que aquí sí se ejercitan el
#      JS y el CSS que van a producción — importmap resuelto, controllers de
#      Stimulus recogidos por `pin_all_from`, Tailwind ya purgado.
#      Se levanta con `bin/system-tests-docker`.
#
# Nunca metas Chrome en la imagen de producción para lograr esto: dejaría de ser
# el artefacto que se despliega, que es justamente lo que se quiere probar.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  SCREEN_SIZE = [1400, 1400]

  if ENV["SELENIUM_REMOTE_URL"].present?
    # Puma debe escuchar en todas las interfaces: el navegador lo alcanza desde
    # otro contenedor, no por localhost.
    Capybara.server_host = "0.0.0.0"
    Capybara.server_port = Integer(ENV.fetch("CAPYBARA_SERVER_PORT", "3001"))

    # Chrome tiene que alcanzar a Puma por la red de Docker. No sirve el nombre
    # del servicio: `docker compose run` crea el contenedor con un nombre
    # generado y el alias `app` no resuelve desde el otro contenedor
    # (ERR_NAME_NOT_RESOLVED). La IP privada del contenedor sí es estable dentro
    # de la red de compose.
    container_ip = Socket.ip_address_list.detect { |a| a.ipv4? && !a.ipv4_loopback? }&.ip_address
    Capybara.app_host = "http://#{ENV.fetch("TEST_APP_HOSTNAME") { container_ip }}:#{Capybara.server_port}"

    driven_by :selenium, using: :headless_chrome, screen_size: SCREEN_SIZE, options: {
      browser: :remote,
      url: ENV["SELENIUM_REMOTE_URL"]
    }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: SCREEN_SIZE
  end
end
