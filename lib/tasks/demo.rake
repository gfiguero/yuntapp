namespace :demo do
  desc "Crea (o reconstruye) la junta de vecinos de demo con datos de prueba"
  task seed: :environment do
    result = DemoJuntaSeeder.call
    puts "Junta de demo creada:"
    result.each { |k, v| puts "  #{k}: #{v}" }
  end

  desc "Elimina la junta de vecinos de demo y todos sus datos"
  task reset: :environment do
    result = DemoJuntaSeeder.reset!
    puts "Demo eliminada: #{result[:association]}"
  end
end
