require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Yuntapp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks scripts generators templates])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Santiago"

    # Las URLs de Active Storage (documentos de identidad, vigencias de directiva)
    # se firman con caducidad: por defecto el signed_id no expira nunca y con el
    # servicio Disk una URL filtrada queda accesible de forma indefinida. El PDF
    # del certificado además no pasa por aquí — se sirve autorizado por el
    # controlador en cada descarga (BR-091/BR-092/BR-141).
    config.active_storage.urls_expire_in = 5.minutes
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
