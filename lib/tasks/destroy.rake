Dir[Rails.root.join("lib/scripts/*.rb")].each { |file| require file }

namespace :yuntapp do
  desc "Destroy scaffolds for yuntapp project"
  task destroy: :environment do
    puts "Starting yuntapp:destroy task..."

    scaffolds = %w[ListingScaffold CategoryScaffold TagScaffold]

    scaffolds.each do |scaffold|
      puts "Destroying #{scaffold}..."
      system(Object.const_get(scaffold.to_s).new.destroy_command)
    end

    puts "Finished yuntapp:destroy task!"
  end
end
