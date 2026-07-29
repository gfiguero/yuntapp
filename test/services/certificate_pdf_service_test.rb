require "test_helper"

class CertificatePdfServiceTest < ActiveSupport::TestCase
  setup do
    @certificate = ResidenceCertificate.create!(
      member: members(:selendis_member),
      household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      purpose: "trámite bancario",
      status: "issued",
      folio: "CR-1-42",
      validation_token: "uuid-test-token",
      validation_code: "ABCD1234",
      issue_date: Date.current,
      expiration_date: Date.current + 30.days,
      issued_at: Time.current
    )
  end

  test "render returns PDF bytes" do
    bytes = CertificatePdfService.new(@certificate).render
    assert bytes.is_a?(String)
    assert bytes.bytesize > 1000, "expected non-trivial PDF size"
    assert bytes.start_with?("%PDF-"), "expected PDF magic bytes"
  end

  test "render does not raise with all expected fields present" do
    assert_nothing_raised do
      CertificatePdfService.new(@certificate).render
    end
  end

  test "generate_and_attach! attaches a pdf_document to the certificate" do
    assert_not @certificate.pdf_document.attached?

    CertificatePdfService.new(@certificate).generate_and_attach!

    assert @certificate.pdf_document.attached?
    assert_equal "application/pdf", @certificate.pdf_document.content_type
    assert_match(/certificado-CR-1-42\.pdf/, @certificate.pdf_document.filename.to_s)
    assert @certificate.pdf_document.byte_size > 1000
  end

  test "render works with members having accented characters in names" do
    @certificate.member.verified_identity.update!(first_name: "Ñoño", last_name: "Pérez Áéíóú")
    assert_nothing_raised do
      CertificatePdfService.new(@certificate.reload).render
    end
  end

  # --- verification_url host resolution (#102) ---

  test "verification_url uses the configured verification_base_url" do
    original = Rails.application.config.x.verification_base_url
    Rails.application.config.x.verification_base_url = "https://staging.example.cl"

    url = CertificatePdfService.new(@certificate).send(:verification_url)
    assert_equal "https://staging.example.cl/verify/#{@certificate.validation_token}", url
  ensure
    Rails.application.config.x.verification_base_url = original
  end

  test "verification_url strips a trailing slash from the configured base" do
    original = Rails.application.config.x.verification_base_url
    Rails.application.config.x.verification_base_url = "https://yuntapp.cl/"

    url = CertificatePdfService.new(@certificate).send(:verification_url)
    assert_equal "https://yuntapp.cl/verify/#{@certificate.validation_token}", url
  ensure
    Rails.application.config.x.verification_base_url = original
  end
end
