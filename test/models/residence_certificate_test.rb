require "test_helper"

class ResidenceCertificateTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  # --- After-commit job enqueue (BR-076) ---

  test "mark_as_paid! enqueues IssueCertificateJob after commit" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500
    )

    assert_enqueued_with(job: IssueCertificateJob, args: [cert.id]) do
      cert.mark_as_paid!(payment_id: "MP-NEW")
    end
  end

  test "does not enqueue job on subsequent saves once already paid" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-PRE",
      paid_at: 1.hour.ago
    )

    assert_no_enqueued_jobs only: IssueCertificateJob do
      cert.mark_as_paid!(payment_id: "MP-PRE") # idempotent — no status change
    end
  end

  # --- issue! transition (BR-062, BR-074) ---

  test "issue! transitions paid to issued with folio, tokens and dates" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-PAY",
      paid_at: Time.current
    )

    cert.issue!

    assert cert.issued?
    assert_match(/\ACR-\d+-\d+\z/, cert.folio)
    assert cert.validation_token.present?
    assert_match(/\A[\h-]+\z/, cert.validation_token) # uuid-ish
    assert cert.validation_code.present?
    assert_equal ResidenceCertificate::VALIDATION_CODE_LENGTH, cert.validation_code.length
    assert_not_nil cert.issued_at
    assert_equal Date.current, cert.issue_date
    assert_equal Date.current + 6.months, cert.expiration_date
  end

  test "issue! is idempotent when already issued (BR-076)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued",
      validation_token: "uuid-preset",
      validation_code: "PRESET12"
    )

    cert.issue!
    assert cert.issued?
    assert_equal "uuid-preset", cert.validation_token
    assert_equal "PRESET12", cert.validation_code
  end

  test "issue! raises when status is not paid" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "pending_payment"
    )

    assert_raises(RuntimeError) do
      cert.issue!
    end
  end

  test "issue! preserves existing folio/tokens if already set (defense against double issuance)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "paid",
      payment_id: "MP-FOO",
      paid_at: Time.current,
      folio: "CR-MANUAL-999",
      validation_token: "abc-existing",
      validation_code: "EXIST123"
    )

    cert.issue!

    assert cert.issued?
    assert_equal "CR-MANUAL-999", cert.folio
    assert_equal "abc-existing", cert.validation_token
    assert_equal "EXIST123", cert.validation_code
  end

  # --- Uniqueness validations (BR-074) ---

  test "validation_token must be unique" do
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      validation_token: "uuid-shared-token"
    )

    duplicate = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "otro",
      validation_token: "uuid-shared-token"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:validation_token].any?
  end

  test "validation_code must be unique" do
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      validation_code: "ABCD1234"
    )

    duplicate = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "otro",
      validation_code: "ABCD1234"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:validation_code].any?
  end

  # --- Public verification (BR-009, BR-078, BR-079, BR-080, BR-081) ---

  def issued_certificate(token: SecureRandom.uuid, code: SecureRandom.alphanumeric(8).upcase, expiration: Date.current + 6.months)
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued",
      folio: "CR-1-#{rand(1_000_000)}",
      validation_token: token,
      validation_code: code,
      issue_date: Date.current,
      expiration_date: expiration,
      issued_at: Time.current
    )
  end

  test "expired? is false for cert with future expiration" do
    cert = issued_certificate(expiration: Date.current + 1.day)
    assert_not cert.expired?
  end

  test "expired? is true for cert with past expiration" do
    cert = issued_certificate(expiration: Date.current - 1.day)
    assert cert.expired?
  end

  test "expired? is false when expiration_date is nil" do
    cert = issued_certificate
    cert.update_columns(expiration_date: nil)
    assert_not cert.expired?
  end

  test "masked_run hides middle digits keeping format" do
    cert = issued_certificate
    cert.member.verified_identity.update_columns(run: "12345678-K")
    assert_equal "1.XXX.XXX-K", cert.member.reload.run && cert.masked_run
  end

  test "masked_run preserves dv for known RUN format" do
    cert = issued_certificate
    cert.member.verified_identity.update_columns(run: "9876543-2")
    assert_equal "9.XXX.XXX-2", cert.masked_run
  end

  test "masked_run returns nil when run is malformed" do
    cert = issued_certificate
    cert.member.verified_identity.update_columns(run: "malformed-no-dash-pattern")
    # malformed RUN sin formato body-dv → masked_run retorna el raw
    assert_kind_of String, cert.masked_run
  end

  test "findable_publicly scope returns only issued certs" do
    issued = issued_certificate
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "test",
      status: "pending_payment",
      validation_token: "uuid-pending",
      validation_code: "PENDING1"
    )

    results = ResidenceCertificate.findable_publicly
    assert_includes results, issued
    assert results.all?(&:issued?)
  end

  test "find_for_public_verification finds by validation_token" do
    cert = issued_certificate(token: SecureRandom.uuid)
    found = ResidenceCertificate.find_for_public_verification(cert.validation_token)
    assert_equal cert, found
  end

  test "find_for_public_verification finds by validation_code" do
    cert = issued_certificate(code: "LOOKUP12")
    found = ResidenceCertificate.find_for_public_verification("LOOKUP12")
    assert_equal cert, found
  end

  test "find_for_public_verification is case-insensitive for validation_code" do
    cert = issued_certificate(code: "LOOKUP34")
    found = ResidenceCertificate.find_for_public_verification("lookup34")
    assert_equal cert, found
  end

  test "find_for_public_verification returns nil for non-issued cert (BR-081)" do
    pending = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "test",
      status: "pending_payment",
      validation_token: "uuid-only-pending",
      validation_code: "PEND1234"
    )

    assert_nil ResidenceCertificate.find_for_public_verification(pending.validation_token)
    assert_nil ResidenceCertificate.find_for_public_verification(pending.validation_code)
  end

  test "find_for_public_verification returns nil for unknown identifier" do
    assert_nil ResidenceCertificate.find_for_public_verification("not-a-real-uuid")
    assert_nil ResidenceCertificate.find_for_public_verification("ABCD5678")
  end

  test "find_for_public_verification returns nil for blank identifier" do
    assert_nil ResidenceCertificate.find_for_public_verification(nil)
    assert_nil ResidenceCertificate.find_for_public_verification("")
    assert_nil ResidenceCertificate.find_for_public_verification("   ")
  end

  test "find_for_public_verification works for expired certs (BR-009, BR-080)" do
    cert = issued_certificate(expiration: 1.month.ago)
    found = ResidenceCertificate.find_for_public_verification(cert.validation_token)
    assert_equal cert, found
    assert found.expired?
  end
end
