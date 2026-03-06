require "simplecov"
SimpleCov.start "rails"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    # parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Copy fixture files to Active Storage's test service directory so blob
    # fixtures can resolve to real files on disk.
    setup do
      fixture_file = Rails.root.join("test/fixtures/files/id_placeholder.png")
      next unless fixture_file.exist?

      service_root = Rails.root.join("tmp/storage")
      ActiveStorage::Blob.all.each do |blob|
        path = service_root.join(blob.key)
        next if path.exist?

        FileUtils.mkdir_p(path.dirname)
        FileUtils.cp(fixture_file, path)
      end
    end
  end
end
