require "test_helper"

class PaymentReversalMailerTest < ActionMailer::TestCase
  test "staff_alert is addressed to the staff and names the payable" do
    staff = users(:artanis) # superadmin con email
    cert = ResidenceCertificate.create!(
      member: members(:selendis_member), household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin), purpose: "t",
      status: "issued", folio: "CR-1-7777", issue_date: Date.current,
      expiration_date: 30.days.from_now.to_date, issued_at: Time.current, payment_status: "charged_back",
      payment_id: "MP-CB-1"
    )
    mail = PaymentReversalMailer.staff_alert(staff, cert)
    assert_equal [staff.email], mail.to
    assert_match cert.folio.to_s, mail.body.encoded
  end

  test "staff_alert returns early (no delivery) when staff has no email" do
    staff = User.new(email: "")
    cert = ResidenceCertificate.new(id: 1, folio: "CR-1-1", payment_status: "refunded")
    mail = PaymentReversalMailer.staff_alert(staff, cert)
    assert_nil mail.message.to
  end
end
