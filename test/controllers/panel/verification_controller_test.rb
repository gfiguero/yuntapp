require "test_helper"

module Panel
  class VerificationControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @karass = users(:karass)
      @selendis = users(:selendis)
      @rohana = users(:rohana)
    end

    # --- show ---

    test "redirects to new when user has no persona" do
      sign_in @karass
      get panel_verification_url
      assert_redirected_to new_panel_verification_url
    end

    test "shows verification status when user has persona" do
      sign_in @selendis
      get panel_verification_url
      assert_response :success
    end

    # --- new ---

    test "renders new form for user without persona" do
      sign_in @karass
      get new_panel_verification_url
      assert_response :success
    end

    test "redirects verified user from new to show" do
      sign_in @selendis
      get new_panel_verification_url
      assert_redirected_to panel_verification_url
    end

    # --- create ---

    test "creates persona and links to user" do
      sign_in @karass

      assert_difference("Persona.count", 1) do
        post panel_verification_url, params: {persona: {
          first_name: "Karass",
          last_name: "Templar",
          run: "77.777.777-7",
          phone: "+56912345678"
        }}
      end

      assert_redirected_to panel_verification_url
      assert_equal I18n.t("persona.message.submitted"), flash[:notice]

      @karass.reload
      assert_not_nil @karass.persona
      assert_equal "77777777-7", @karass.persona.run
      assert_equal "pending", @karass.persona.verification_status
    end

    test "finds existing persona by RUN if not claimed by another user" do
      sign_in @rohana

      # karass_persona exists with run 222222222 and no user linked
      karass_persona = personas(:karass_persona)
      karass_persona.update!(user: nil) # ensure no user

      assert_no_difference("Persona.count") do
        post panel_verification_url, params: {persona: {
          first_name: "Karass",
          last_name: "Templar",
          run: "222222222",
          phone: "+56987654321"
        }}
      end

      assert_redirected_to panel_verification_url
      @rohana.reload
      assert_equal karass_persona, @rohana.persona
    end

    test "rejects RUN already claimed by another user" do
      sign_in @karass

      # selendis_persona is already linked to selendis user
      post panel_verification_url, params: {persona: {
        first_name: "Fake",
        last_name: "Person",
        run: "111111111",
        phone: "+56900000000"
      }}

      assert_redirected_to new_panel_verification_url
      assert_equal I18n.t("persona.message.run_already_claimed"), flash[:alert]
    end

    test "redirects verified user trying to create" do
      sign_in @selendis

      assert_no_difference("Persona.count") do
        post panel_verification_url, params: {persona: {
          first_name: "Selendis",
          last_name: "Daelaam",
          run: "999999999",
          phone: "+56912345678"
        }}
      end

      assert_redirected_to panel_verification_url
    end
  end
end
