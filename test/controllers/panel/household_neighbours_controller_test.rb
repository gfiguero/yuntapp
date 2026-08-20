require "test_helper"

module Panel
  # BR-042: el household_admin ve QUÉ otros núcleos familiares conviven en su
  # dirección, en solo lectura. BR-041 le prohíbe ver a sus residentes, así que
  # esta vista muestra recuentos, nunca nombres ni RUN.
  class HouseholdNeighboursControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @household_admin = users(:selendis)
      @non_admin = users(:karass)
      @family_group = family_groups(:selendis_family_group)
      @household_unit = @family_group.household_unit
    end

    # --- Authorization ---

    test "redirects when user is not signed in" do
      get panel_household_neighbours_url
      assert_redirected_to new_user_session_url
    end

    test "redirects when user is not household_admin" do
      sign_in @non_admin
      get panel_household_neighbours_url
      assert_redirected_to panel_root_url
    end

    # --- Contenido ---

    test "shows the address of the household" do
      sign_in @household_admin
      get panel_household_neighbours_url

      assert_response :success
    end

    test "counts the other family groups sharing the address" do
      FamilyGroup.create!(household_unit: @household_unit)

      sign_in @household_admin
      get panel_household_neighbours_url

      assert_response :success
      assert_match I18n.t("panel.household_neighbours.index.count", count: 1), response.body
      assert_no_match I18n.t("panel.household_neighbours.index.alone"), response.body
    end

    test "does not count family groups from another address" do
      FamilyGroup.create!(household_unit: household_units(:matching_karax_household))

      sign_in @household_admin
      get panel_household_neighbours_url

      assert_response :success
      assert_match I18n.t("panel.household_neighbours.index.alone"), response.body
    end

    test "shows how many residents each other family group has" do
      other = FamilyGroup.create!(household_unit: @household_unit)
      Residency.create!(
        verified_identity: verified_identities(:karass_persona),
        verified_residence: residencies(:selendis_residency).verified_residence,
        household_unit: @household_unit,
        family_group: other,
        household_admin: true,
        status: "approved"
      )

      sign_in @household_admin
      get panel_household_neighbours_url

      assert_match I18n.t("panel.household_neighbours.index.residents", count: 1), response.body
    end

    # El corazón de la regla: contexto sí, datos personales no (BR-041).
    test "never leaks the names or RUN of residents from another family group" do
      other = FamilyGroup.create!(household_unit: @household_unit)
      neighbour_identity = verified_identities(:karass_persona)
      Residency.create!(
        verified_identity: neighbour_identity,
        verified_residence: residencies(:selendis_residency).verified_residence,
        household_unit: @household_unit,
        family_group: other,
        household_admin: true,
        status: "approved"
      )

      sign_in @household_admin
      get panel_household_neighbours_url

      assert_response :success
      assert_no_match neighbour_identity.first_name, response.body
      assert_no_match neighbour_identity.last_name, response.body
      assert_no_match neighbour_identity.run, response.body
    end
  end
end
