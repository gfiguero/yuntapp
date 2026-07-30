require "test_helper"

class GuideControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store.clear if defined?(Rack::Attack)
  end

  test "es accesible sin autenticación" do
    get guide_url
    assert_response :success
  end
end
