require "test_helper"

class ResidenceCertificateTest < ActiveSupport::TestCase
  def setup
    @member = members(:selendis_member)
    @household_unit = household_units(:selendis_household)
    @association = neighborhood_associations(:manios_de_buin)
  end

  test "valid statuses are pending_payment, paid, issued" do
    %w[pending_payment paid issued].each do |status|
      cert = ResidenceCertificate.new(
        member: @member,
        household_unit: @household_unit,
        neighborhood_association: @association,
        purpose: "trámite bancario",
        status: status
      )
      assert cert.valid?, "#{status} debería ser válido pero falló: #{cert.errors.full_messages}"
    end
  end

  test "approved and rejected are not valid statuses" do
    %w[approved rejected pending].each do |status|
      cert = ResidenceCertificate.new(
        member: @member,
        household_unit: @household_unit,
        neighborhood_association: @association,
        purpose: "trámite bancario",
        status: status
      )
      assert_not cert.valid?, "#{status} no debería ser un estado válido"
    end
  end

  test "pending_payment? returns true when status is pending_payment" do
    cert = ResidenceCertificate.new(status: "pending_payment")
    assert cert.pending_payment?
    assert_not cert.paid?
    assert_not cert.issued?
  end

  test "paid? returns true when status is paid" do
    cert = ResidenceCertificate.new(status: "paid")
    assert cert.paid?
    assert_not cert.pending_payment?
    assert_not cert.issued?
  end

  test "issued? returns true when status is issued" do
    cert = ResidenceCertificate.new(status: "issued")
    assert cert.issued?
    assert_not cert.pending_payment?
    assert_not cert.paid?
  end

  test "new certificate defaults to pending_payment status" do
    cert = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario"
    )
    assert_equal "pending_payment", cert.status
  end

  test "generate_folio! sets folio with correct format" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "pending_payment"
    )
    cert.generate_folio!
    assert_match(/\ACR-\d+-\d+\z/, cert.folio)
  end

  # BR-008: issued certificates are immutable
  test "issued certificate cannot be modified" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued"
    )
    assert_not cert.update(purpose: "otro propósito")
    assert cert.errors[:base].any?
    cert.reload
    assert_equal "trámite bancario", cert.purpose
  end

  test "issued certificate raises on update!" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued"
    )
    assert_raises(ActiveRecord::RecordInvalid) do
      cert.update!(purpose: "otro propósito")
    end
  end

  test "paid certificate can be transitioned to issued" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "paid"
    )
    assert cert.update(status: "issued", issue_date: Date.current, expiration_date: 6.months.from_now.to_date)
  end

  test "pending_payment certificate can be modified" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "pending_payment"
    )
    assert cert.update(purpose: "arriendo")
  end

  # --- BR-005 minimum amount + BR-004 platform fee ---

  test "rejects amount below 1000 (BR-005)" do
    cert = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 999
    )
    assert_not cert.valid?
    assert cert.errors[:amount].any?
  end

  test "accepts amount at 1000" do
    cert = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1000
    )
    assert cert.valid?
  end

  test "amount is optional (legacy records may not have it)" do
    cert = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario"
    )
    assert cert.valid?
  end

  test "platform_fee is computed as 10 percent of amount (BR-004)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500
    )
    assert_equal 150, cert.platform_fee
  end

  test "platform_fee not overwritten if already set" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      platform_fee: 500
    )
    assert_equal 500, cert.platform_fee
  end

  test "platform_fee uses integer division (CLP has no decimals)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1234
    )
    assert_equal 123, cert.platform_fee
  end

  # --- payment_id uniqueness (BR-071) ---

  test "payment_id must be unique" do
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      payment_id: "MP-12345"
    )

    duplicate = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "otro",
      amount: 1500,
      payment_id: "MP-12345"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:payment_id].any?
  end

  test "payment_id allows nil for multiple certificates" do
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500
    )

    another = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "arriendo",
      amount: 1500
    )
    assert another.valid?
  end

  # --- mark_as_paid! ---

  test "mark_as_paid! transitions pending_payment to paid" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500
    )

    cert.mark_as_paid!(payment_id: "MP-XYZ")

    assert cert.paid?
    assert_equal "MP-XYZ", cert.payment_id
    assert_not_nil cert.paid_at
  end

  test "mark_as_paid! is idempotent on already-paid certificate with same payment_id (BR-071)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-XYZ",
      paid_at: 1.hour.ago
    )
    original_paid_at = cert.paid_at

    cert.mark_as_paid!(payment_id: "MP-XYZ")

    assert cert.paid?
    assert_equal "MP-XYZ", cert.payment_id
    assert_equal original_paid_at.to_i, cert.paid_at.to_i
  end

  test "mark_as_paid! raises when already paid with different payment_id" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-XYZ",
      paid_at: 1.hour.ago
    )

    assert_raises(ResidenceCertificate::AlreadyPaidError) do
      cert.mark_as_paid!(payment_id: "MP-DIFFERENT")
    end
  end

  test "mark_as_paid! refuses to downgrade from issued (BR-008)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued"
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      cert.mark_as_paid!(payment_id: "MP-XYZ")
    end
  end
end
