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
end
