namespace :yuntapp do
  desc "Copy fixture files to Active Storage disk service directory"
  task copy_fixture_files: :environment do
    service = ActiveStorage::Blob.services.fetch(Rails.configuration.active_storage.service)

    unless service.is_a?(ActiveStorage::Service::DiskService)
      puts "Skipping: Active Storage service is not Disk"
      next
    end

    ActiveStorage::Blob.where("key LIKE ?", "fixture_%").find_each do |blob|
      source = Rails.root.join("test/fixtures/files", blob.filename.to_s)

      unless source.exist?
        puts "Source file not found: #{source}"
        next
      end

      if service.exist?(blob.key)
        puts "Already exists: #{blob.key} (#{blob.filename})"
      else
        service.upload(blob.key, source.open, checksum: blob.checksum)
        puts "Copied: #{blob.key} -> #{blob.filename}"
      end
    end

    puts "Done!"
  end
end
