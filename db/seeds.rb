# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Geografía de Chile: Country → 16 regiones → 346 comunas (CUT oficial).
# Idempotente; re-ejecutable sin duplicar. Ver ChileGeographySeeder.
country = ChileGeographySeeder.call
puts "Geografía de Chile: #{country.regions.count} regiones, " \
  "#{Commune.where(region: country.regions).count} comunas."
