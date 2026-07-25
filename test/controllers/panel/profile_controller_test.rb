require "test_helper"

class Panel::ProfileControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "show renders the profile for a signed-in user" do
    sign_in users(:selendis)
    get panel_profile_url
    assert_response :success
    assert_match "Mi Perfil", @response.body
  end

  test "show links to Mi Cuenta for password changes (BR-094)" do
    sign_in users(:selendis)
    get panel_profile_url
    assert_match edit_user_registration_path, @response.body
  end

  test "unauthenticated is redirected to login" do
    get panel_profile_url
    assert_redirected_to new_user_session_url
  end

  # BR-094: el perfil es solo consulta — la ruta de update no existe y la
  # contraseña no puede cambiarse desde aquí.
  test "profile update route does not exist" do
    user = users(:selendis)
    sign_in user

    patch panel_profile_url, params: {user: {password: "hackeada-123", password_confirmation: "hackeada-123"}}

    assert_response :not_found
    assert_not user.reload.valid_password?("hackeada-123")
  end
end
