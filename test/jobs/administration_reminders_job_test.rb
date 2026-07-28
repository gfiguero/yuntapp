require "test_helper"

class AdministrationRemindersJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "encola un digest por cada superadmin cuando hay pendientes" do
    superadmins = User.where(superadmin: true).where.not(email: nil).count
    assert_operator superadmins, :>, 0, "se requiere al menos un superadmin con email en fixtures"

    assert_enqueued_emails superadmins do
      AdministrationRemindersJob.perform_now
    end
  end
end
