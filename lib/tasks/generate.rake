Dir[Rails.root.join("lib/scripts/*.rb")].each { |file| require file }

namespace :yuntapp do
  desc "Generate scaffolds for yuntapp project"
  task generate: :environment do
    puts "Starting yuntapp:generate task..."

    scaffolds = %w[ListingScaffold TagScaffold CategoryScaffold]

    scaffolds.each do |scaffold|
      puts "Generating #{scaffold}..."
      system(Object.const_get(scaffold.to_s).new.generate_command)
    end

    puts "Finished yuntapp:generate task!"
  end
end
