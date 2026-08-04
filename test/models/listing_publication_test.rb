require "test_helper"

# Ciclo de publicación pagada del marketplace (BR-083, BR-085, BR-086, BR-087).
class ListingPublicationTest < ActiveSupport::TestCase
  setup do
    @listing = Listing.create!(name: "Test listing", user: users(:artanis))
  end

  test "new listing starts as pending_payment (BR-083)" do
    assert @listing.pending_payment?
    assert_not @listing.published?
    assert @listing.payable?
  end

  test "mark_as_paid! publishes for 30 days (BR-086)" do
    @listing.mark_as_paid!(payment_id: "MP-1")

    assert @listing.published?
    assert_equal "MP-1", @listing.payment_id
    assert_equal Date.current + 30.days, @listing.published_until
    assert_not @listing.payable?
  end

  # BR-004/BR-085/BR-145: el cobro recurrente es por `subscription_amount` (fijo
  # al autorizar), pero `amount` se reescribe con el precio vigente cada vez que
  # el usuario abre "pagar". Sin re-sincronizar, la publicación renovada quedaba
  # registrando un 10% sobre un monto que nadie pagó.
  test "renew_from_subscription! sincroniza el snapshot con el monto cobrado (BR-004/BR-085)" do
    @listing.update!(subscription_amount: 1000, amount: 2000, platform_fee: 200)

    @listing.renew_from_subscription!(payment_id: "MP-SUB-FEE")

    @listing.reload
    assert_equal 1000, @listing.amount, "el snapshot debe reflejar el monto realmente cobrado"
    assert_equal 100, @listing.platform_fee, "la comisión es el 10% del monto cobrado"
  end

  test "renew_from_subscription! cae a amount si no hay snapshot de suscripción (BR-145)" do
    @listing.update!(subscription_amount: nil, amount: 3000, platform_fee: nil)

    @listing.renew_from_subscription!(payment_id: "MP-SUB-LEGACY")

    @listing.reload
    assert_equal 3000, @listing.amount
    assert_equal 300, @listing.platform_fee
  end

  test "mark_as_paid! is idempotent for same payment_id (BR-087)" do
    @listing.mark_as_paid!(payment_id: "MP-1")
    original_until = @listing.published_until

    @listing.mark_as_paid!(payment_id: "MP-1")
    assert_equal original_until, @listing.reload.published_until
  end

  test "mark_as_paid! raises for different payment_id while published (BR-087)" do
    @listing.mark_as_paid!(payment_id: "MP-1")

    assert_raises(Listing::AlreadyPaidError) do
      @listing.mark_as_paid!(payment_id: "MP-2")
    end
  end

  test "expired publication can be renewed with a new payment (BR-086)" do
    @listing.mark_as_paid!(payment_id: "MP-1")
    @listing.update_columns(published_until: 2.days.ago.to_date)

    assert @listing.publication_expired?
    assert @listing.payable?

    @listing.mark_as_paid!(payment_id: "MP-2")
    assert @listing.published?
    assert_equal Date.current + 30.days, @listing.published_until
  end

  test "platform fee is 10 percent of amount (BR-085)" do
    @listing.update!(amount: 1500)
    assert_equal 150, @listing.platform_fee
  end

  # --- Auto-renovación por suscripción (BR-088/BR-089) ---

  test "renew_from_subscription! publishes a pending listing 30 days from payment" do
    @listing.renew_from_subscription!(payment_id: "MP-SUB-1")

    assert @listing.published?
    assert_equal Date.current + 30.days, @listing.published_until
  end

  test "renew_from_subscription! extends from current expiry when still published (BR-089)" do
    @listing.mark_as_paid!(payment_id: "MP-SUB-1")
    current_until = @listing.published_until

    @listing.renew_from_subscription!(payment_id: "MP-SUB-2")
    assert_equal current_until + 30.days, @listing.published_until
  end

  test "renew_from_subscription! extends from payment date when expired (BR-089)" do
    @listing.mark_as_paid!(payment_id: "MP-SUB-1")
    @listing.update_columns(published_until: 10.days.ago.to_date)

    @listing.renew_from_subscription!(payment_id: "MP-SUB-2")
    assert_equal Date.current + 30.days, @listing.published_until
  end

  test "renew_from_subscription! is idempotent for same payment_id (BR-087)" do
    @listing.renew_from_subscription!(payment_id: "MP-SUB-1")
    original_until = @listing.published_until

    @listing.renew_from_subscription!(payment_id: "MP-SUB-1")
    assert_equal original_until, @listing.reload.published_until
  end

  test "subscribable when payable without active subscription" do
    assert @listing.subscribable?

    @listing.update!(subscription_status: "authorized")
    assert_not @listing.subscribable?

    @listing.update!(subscription_status: "cancelled")
    assert @listing.subscribable?
  end

  test "published scope excludes pending and expired" do
    published = Listing.create!(name: "published", user: users(:artanis))
    published.mark_as_paid!(payment_id: "MP-scope-1")

    expired = Listing.create!(name: "expired", user: users(:artanis))
    expired.mark_as_paid!(payment_id: "MP-scope-2")
    expired.update_columns(published_until: 1.day.ago.to_date)

    assert_includes Listing.published, published
    assert_not_includes Listing.published, expired
    assert_not_includes Listing.published, @listing
  end

  # --- Task 2: apply_mp_payment_status! en Listing ---

  test "apply_mp_payment_status! unpublishes a listing whose payment was reverted" do
    listing = Listing.create!(name: "Pub", user: users(:artanis), amount: 1200)
    listing.mark_as_paid!(payment_id: "MP-LREV-1")
    assert listing.published?
    listing.apply_mp_payment_status!("charged_back")
    assert_equal "charged_back", listing.payment_status
    assert listing.pending_payment?
    assert_nil listing.published_until
  end

  test "apply_mp_payment_status! registers non-reverted status without unpublishing" do
    listing = Listing.create!(name: "Pub", user: users(:artanis), amount: 1200)
    listing.mark_as_paid!(payment_id: "MP-LREV-2")
    listing.apply_mp_payment_status!("in_process")
    assert_equal "in_process", listing.payment_status
    assert listing.published?
  end

  test "apply_mp_payment_status! is idempotent for the same status on listing" do
    listing = Listing.create!(name: "Pub", user: users(:artanis), amount: 1200, payment_status: "in_process")
    assert_no_changes -> { listing.reload.updated_at } do
      listing.apply_mp_payment_status!("in_process")
    end
  end

  # --- #109: snapshot de precio inmutable mientras la publicación está vigente ---

  test "amount cannot change while the publication is live (#109)" do
    listing = Listing.create!(name: "Vigente", user: users(:artanis), amount: 1200)
    listing.mark_as_paid!(payment_id: "MP-IMMUT-1")
    assert listing.published?

    listing.amount = 5000
    assert_not listing.valid?, "no debe permitirse cambiar amount de una publicación vigente"
    assert listing.errors[:base].any?
  end

  test "amount can be re-captured once the publication expired (renewal, #109)" do
    listing = Listing.create!(name: "Vencida", user: users(:artanis), amount: 1200)
    listing.mark_as_paid!(payment_id: "MP-IMMUT-2")
    listing.update_column(:published_until, 1.day.ago.to_date) # vence
    assert listing.publication_expired?

    listing.amount = 2000
    assert listing.valid?, "una publicación vencida sí puede re-capturar el precio para renovar"
    assert listing.save
  end

  # --- BR-100: el historial financiero de una publicación no se destruye ---

  test "a paid listing cannot be destroyed (BR-100)" do
    @listing.update!(amount: 1000)
    @listing.mark_as_paid!(payment_id: "MP-NODESTROY-1")

    assert_no_difference -> { Listing.count } do
      assert_not @listing.destroy
    end

    assert Listing.exists?(@listing.id)
    assert_not_empty @listing.errors[:base]
  end

  test "an unpaid draft listing can be destroyed (BR-100)" do
    assert @listing.pending_payment?
    assert_not @listing.ever_paid?

    assert_difference -> { Listing.count }, -1 do
      assert @listing.destroy
    end
  end

  # Una publicación vencida ya generó ingreso: su snapshot financiero (amount,
  # platform_fee, junta beneficiaria — BR-085) sigue siendo dato consolidado.
  test "an expired listing still counts as paid history (BR-100)" do
    @listing.update!(amount: 1000)
    @listing.mark_as_paid!(payment_id: "MP-NODESTROY-2")
    @listing.update_columns(published_until: 1.day.ago.to_date)

    assert @listing.ever_paid?
    assert_not @listing.destroy
  end

  test "withdraw! keeps the record but removes it from the storefront (BR-100)" do
    @listing.update!(amount: 1000)
    @listing.mark_as_paid!(payment_id: "MP-WITHDRAW-1")
    assert_includes Listing.published, @listing

    @listing.withdraw!

    assert Listing.exists?(@listing.id)
    assert_equal false, @listing.reload.active
    assert_not_includes Listing.published, @listing
    # El pago no se toca: la vigencia comprada sigue registrada.
    assert_equal "MP-WITHDRAW-1", @listing.payment_id
    assert_equal Date.current + 30.days, @listing.published_until
  end

  # --- #108: un solo household_admin por FamilyGroup a nivel de BD ---

  test "DB rejects a second household_admin residency in the same family_group (#108)" do
    hu = household_units(:selendis_household)
    fg = family_groups(:selendis_family_group)
    vr = verified_residences(:selendis_verified_residence)
    other_identity = VerifiedIdentity.create!(
      run: "7000001-6", first_name: "Otro", last_name: "Admin",
      phone: "+56911112222", email: "otro.admin.108@example.com"
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      Residency.create!(
        verified_identity: other_identity, verified_residence: vr,
        household_unit: hu, family_group: fg, household_admin: true, status: "approved"
      )
    end
  end
end
