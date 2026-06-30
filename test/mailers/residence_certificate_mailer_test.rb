require "test_helper"

class ResidenceCertificateMailerTest < ActionMailer::TestCase
  setup do
    @certificate = ResidenceCertificate.create!(
      member: members(:selendis_member),
      household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      purpose: "trámite bancario",
      status: "issued",
      folio: "CR-1-901",
      validation_token: "uuid-mail-test",
      validation_code: "MAILCODE",
      issue_date: Date.current,
      expiration_date: Date.current + 6.months,
      issued_at: Time.current
    )
  end

  test "issued sends to member.user.email with folio + validation_code" do
    email = ResidenceCertificateMailer.issued(@certificate)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [users(:selendis).email], email.to
    assert_equal [ENV.fetch("MAILER_DEFAULT_FROM", "no-reply@yuntapp.cl")], email.from
    assert_match @certificate.folio, email.body.encoded
    assert_match @certificate.validation_code, email.body.encoded
    assert_match "/verify/uuid-mail-test", email.body.encoded
  end

  test "subject comes from i18n" do
    email = ResidenceCertificateMailer.issued(@certificate)
    assert_equal I18n.t("residence_certificate_mailer.issued.subject"), email.subject
  end

  test "issued is a no-op when recipient has no email" do
    orphan_identity = VerifiedIdentity.create!(
      first_name: "Sin",
      last_name: "Email",
      run: "98765432-5",
      email: nil
    )
    dependent_member = Member.create!(
      verified_identity: orphan_identity,
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      status: "approved",
      dependent: true,
      requested_by: nil
    )
    orphan_cert = ResidenceCertificate.create!(
      member: dependent_member,
      household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      purpose: "trámite",
      status: "issued",
      folio: "CR-1-902",
      validation_token: "uuid-orphan",
      validation_code: "ORPHAN12",
      issue_date: Date.current,
      expiration_date: Date.current + 6.months,
      issued_at: Time.current
    )

    assert_no_emails do
      ResidenceCertificateMailer.issued(orphan_cert).deliver_now
    end
  end

  test "dependent member email goes to requested_by (household_admin)" do
    orphan_identity = VerifiedIdentity.create!(
      first_name: "Hijo",
      last_name: "Dependiente",
      run: "99999998-0",
      email: nil
    )
    dependent_member = Member.create!(
      verified_identity: orphan_identity,
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      status: "approved",
      dependent: true,
      requested_by: users(:selendis)
    )
    dep_cert = ResidenceCertificate.create!(
      member: dependent_member,
      household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      purpose: "trámite del hijo",
      status: "issued",
      folio: "CR-1-903",
      validation_token: "uuid-dep",
      validation_code: "DEPCODE1",
      issue_date: Date.current,
      expiration_date: Date.current + 6.months,
      issued_at: Time.current
    )

    email = ResidenceCertificateMailer.issued(dep_cert)
    assert_equal [users(:selendis).email], email.to
  end
end
