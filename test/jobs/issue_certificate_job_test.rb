require "test_helper"

class IssueCertificateJobTest < ActiveJob::TestCase
  setup do
    @certificate = ResidenceCertificate.create!(
      member: members(:selendis_member),
      household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-JOB-TEST",
      paid_at: Time.current
    )
  end

  test "perform issues the certificate and attaches a PDF" do
    IssueCertificateJob.new.perform(@certificate.id)

    @certificate.reload
    assert @certificate.issued?
    assert @certificate.folio.present?
    assert @certificate.validation_token.present?
    assert @certificate.validation_code.present?
    assert @certificate.pdf_document.attached?
  end

  test "perform is a no-op when certificate is already issued" do
    @certificate.update!(
      status: "issued",
      folio: "CR-1-100",
      validation_token: "preset-token",
      validation_code: "PRESET12"
    )

    IssueCertificateJob.new.perform(@certificate.id)

    @certificate.reload
    assert_equal "preset-token", @certificate.validation_token
    assert_equal "PRESET12", @certificate.validation_code
    assert_not @certificate.pdf_document.attached? # no se regenera
  end

  test "perform is a no-op when certificate is not paid" do
    @certificate.update_columns(status: "pending_payment")

    IssueCertificateJob.new.perform(@certificate.id)

    @certificate.reload
    assert @certificate.pending_payment?
  end

  test "perform handles missing certificate gracefully" do
    assert_nothing_raised do
      IssueCertificateJob.new.perform(999999)
    end
  end
end
