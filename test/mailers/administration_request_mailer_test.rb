require "test_helper"

class AdministrationRequestMailerTest < ActionMailer::TestCase
  test "submitted se envía al solicitante" do
    req = administration_requests(:pending_manios)
    mail = AdministrationRequestMailer.submitted(req)
    assert_equal [req.user.email], mail.to
    assert mail.subject.present?
  end

  test "approved se envía al solicitante" do
    req = administration_requests(:pending_manios)
    mail = AdministrationRequestMailer.approved(req)
    assert_equal [req.user.email], mail.to
  end
end
