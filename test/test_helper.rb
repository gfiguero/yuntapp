require "simplecov"
SimpleCov.start "rails"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Minitest 6 removed `Object#stub`. This helper restores a minimal version
# of the pattern for stubbing class methods within a test block.
module StubClassMethod
  def stub_class_method(klass, method, return_value_or_proc)
    original = klass.method(method)
    klass.define_singleton_method(method) do |*args, **kw|
      return_value_or_proc.respond_to?(:call) ? return_value_or_proc.call(*args, **kw) : return_value_or_proc
    end
    yield
  ensure
    klass.singleton_class.send(:remove_method, method)
    klass.define_singleton_method(method, original)
  end
end

# Helper para RUT válido y único en tests (rango 62.000.000+seq).
module ValidTestRut
  def valid_test_rut(seq)
    body = (62_000_000 + seq).to_s
    sum = 0
    m = 2
    body.reverse.each_char { |c|
      sum += c.to_i * m
      m = (m == 7) ? 2 : m + 1
    }
    r = 11 - (sum % 11)
    dv = if r == 11
      "0"
    else
      ((r == 10) ? "K" : r.to_s)
    end
    "#{body}-#{dv}"
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    # parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include StubClassMethod
    include ValidTestRut

    # Add more helper methods to be used by all tests here...

    # Copy fixture files to Active Storage's test service directory so blob
    # fixtures can resolve to real files on disk.
    setup do
      fixture_file = Rails.root.join("test/fixtures/files/id_placeholder.png")
      next unless fixture_file.exist?

      service_root = Rails.root.join("tmp/storage")
      ActiveStorage::Blob.all.find_each do |blob|
        path = service_root.join(blob.key)
        next if path.exist?

        FileUtils.mkdir_p(path.dirname)
        FileUtils.cp(fixture_file, path)
      end
    end
  end
end

class ActionDispatch::IntegrationTest
  include StubClassMethod
  include ValidTestRut
end
