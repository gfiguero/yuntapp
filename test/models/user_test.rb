require "test_helper"

class UserTest < ActiveSupport::TestCase
  # --- Auto-desactivación (reversible por el usuario) ---

  test "active_for_authentication? is false when deactivated" do
    user = users(:karax)
    assert user.active_for_authentication?
    user.deactivate!
    assert_not user.active_for_authentication?
    assert user.deactivated?
  end

  test "reactivate! restores authentication" do
    user = users(:karax)
    user.deactivate!
    user.reactivate!
    assert_nil user.reload.deactivated_at
    assert user.active_for_authentication?
  end

  test "reactivate! does nothing when the account is blocked" do
    user = users(:karax)
    user.deactivate!
    user.block!(by: users(:artanis), reason: "Abuso")
    user.reactivate!
    assert user.reload.deactivated?, "sigue desactivada: una cuenta bloqueada no se auto-reactiva"
    assert user.blocked?
  end

  # --- Bloqueo por superadmin (no reversible por el usuario) ---

  test "block! blocks authentication and records who and why" do
    user = users(:karax)
    admin = users(:artanis)
    user.block!(by: admin, reason: "Fraude")
    assert user.blocked?
    assert_equal admin, user.blocked_by
    assert_equal "Fraude", user.block_reason
    assert_not user.active_for_authentication?
  end

  test "unblock! restores authentication" do
    user = users(:karax)
    user.block!(by: users(:artanis), reason: "x")
    user.unblock!
    assert_not user.reload.blocked?
    assert user.active_for_authentication?
  end

  # --- Cascada (nada se borra) ---

  test "deactivate! cascades to members and unpublishes listings" do
    user = users(:selendis)
    member = members(:selendis_member)
    listing = Listing.create!(user: user, name: "Silla de madera", active: true)

    user.deactivate!

    assert member.reload.inactive?, "las membresías activas pasan a inactive"
    assert_not listing.reload.active?, "las publicaciones se despublican"
  end

  test "deactivate! cancels pending onboarding requests" do
    user = users(:karax)
    onboarding = onboarding_requests(:karax_pending)
    assert onboarding.pending?

    user.deactivate!

    assert onboarding.reload.cancelled?
  end

  # --- BR-100: nunca se destruye ---

  test "a user cannot be destroyed" do
    user = users(:karax)
    assert_not user.destroy, "destroy debe bloquearse"
    assert User.exists?(user.id)
    assert_raises(ActiveRecord::RecordNotDestroyed) { user.destroy! }
  end
end
