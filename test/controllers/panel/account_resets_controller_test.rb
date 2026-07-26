require "test_helper"

module Panel
  class AccountResetsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = users(:selendis)
      @member = members(:selendis_member)
      @dependent = members(:dependent_member)
    end

    # BR-030: restablecer la cuenta NO destruye datos; desactiva y desvincula.
    test "reset deactivates members and preserves history instead of destroying" do
      sign_in @user
      identity = @user.verified_identity

      assert_no_difference [-> { Member.count }, -> { VerifiedIdentity.count }, -> { Residency.count }] do
        delete panel_reset_account_url
      end

      assert_redirected_to panel_root_url

      assert @member.reload.inactive?, "la membresía del socio debe quedar inactive"
      assert @dependent.reload.inactive?, "los dependientes deben quedar inactive en cascada"
      assert VerifiedIdentity.exists?(identity.id), "la identidad verificada debe conservarse"

      @user.reload
      assert_nil @user.verified_identity, "la cuenta se desvincula de la identidad"
      assert_not @user.admin?
      assert_nil @user.neighborhood_association
    end

    test "reset without verified identity just unlinks the account" do
      user = users(:karax) # sin verified_identity
      sign_in user

      delete panel_reset_account_url

      assert_redirected_to panel_root_url
      assert_not user.reload.admin?
    end
  end
end
