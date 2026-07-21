require "yaml"

# Puebla la jerarquía geográfica de Chile (Country → Region → Commune) desde
# el dataset oficial versionado en db/seeds/chile.yml. Idempotente: identifica
# cada registro por su Código Único Territorial (CUT), por lo que re-ejecutarlo
# no crea duplicados. Verifica el conteo esperado (16 regiones, 346 comunas) y
# revierte todo si no cuadra.
class ChileGeographySeeder
  DATA_PATH = Rails.root.join("db/seeds/chile.yml")
  EXPECTED_REGIONS = 16
  EXPECTED_COMMUNES = 346

  class ChecksumError < StandardError; end

  def self.call(path: DATA_PATH)
    new(path).call
  end

  def initialize(path = DATA_PATH)
    @data = YAML.safe_load_file(path)
  end

  def call
    ActiveRecord::Base.transaction do
      country = seed_country
      @data.fetch("regions").each { |region_data| seed_region(country, region_data) }
      verify!(country)
      country
    end
  end

  private

  def seed_country
    attrs = @data.fetch("country")
    country = Country.find_or_initialize_by(iso_code: attrs.fetch("iso_code"))
    country.update!(name: attrs.fetch("name"))
    country
  end

  def seed_region(country, region_data)
    region = country.regions.find_or_initialize_by(code: region_data.fetch("code"))
    region.update!(name: region_data.fetch("name"), position: region_data.fetch("position"))
    region_data.fetch("communes").each do |commune_data|
      commune = region.communes.find_or_initialize_by(code: commune_data.fetch("code"))
      commune.update!(name: commune_data.fetch("name"))
    end
  end

  def verify!(country)
    # Cuenta solo registros con CUT (los que gestiona el seed), ignorando
    # datos preexistentes sin código (p. ej. fixtures de test).
    regions = country.regions.where.not(code: nil).count
    communes = Commune.where(region: country.regions).where.not(code: nil).count
    return if regions == EXPECTED_REGIONS && communes == EXPECTED_COMMUNES

    raise ChecksumError,
      "Seed inconsistente: #{regions}/#{EXPECTED_REGIONS} regiones, " \
      "#{communes}/#{EXPECTED_COMMUNES} comunas"
  end
end
