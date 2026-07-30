require "test_helper"

class GuideControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store.clear if defined?(Rack::Attack)
  end

  test "es accesible sin autenticación" do
    get guide_url
    assert_response :success
  end

  test "renderiza la portada y monta el deck" do
    get guide_url
    assert_response :success
    assert_select "[data-controller='deck']"
    assert_select "h2", text: "¿Cómo funciona Yuntapp?"
  end

  test "incluye los pasos del flujo simple y la bifurcación opcional" do
    get guide_url
    assert_select "h2", text: "Se hace socia de su junta"
    assert_select "h2", text: "Paga en línea"
    # La bifurcación del Acto 2 salta al cierre con un índice explícito.
    assert_select "[data-deck-index-param]"
  end

  test "incluye los conceptos del Acto 2 y el cierre" do
    get guide_url
    assert_select "h2", text: "Una idea clave"
    assert_select "h2", text: "Nada se borra"
    assert_select "h2", text: "Eso es Yuntapp"
  end
end
