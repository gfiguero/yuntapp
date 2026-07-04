require "test_helper"

class OnboardingReminderMailerTest < ActionMailer::TestCase
  setup do
    @admin = users(:selendis)
    @requests = OnboardingRequest.pending.where(neighborhood_association: @admin.neighborhood_association)
  end

  test "pending_digest sends to the admin email" do
    email = OnboardingReminderMailer.pending_digest(@admin, @requests)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@admin.email], email.to
    assert_equal [ENV.fetch("MAILER_DEFAULT_FROM", "no-reply@yuntapp.cl")], email.from
  end

  test "subject comes from i18n with the pending count" do
    email = OnboardingReminderMailer.pending_digest(@admin, @requests)

    assert_equal I18n.t("onboarding_reminder_mailer.pending_digest.subject", count: @requests.size), email.subject
  end

  test "body shows the pending count and a link to the admin panel" do
    email = OnboardingReminderMailer.pending_digest(@admin, @requests)
    body = email.body.encoded

    assert_match @requests.size.to_s, body
    assert_match "/admin/onboarding_requests", body
  end

  test "pending_digest is a no-op when there are no pending requests" do
    empty = OnboardingRequest.none
    email = OnboardingReminderMailer.pending_digest(@admin, empty)

    assert_emails 0 do
      email.deliver_now
    end
  end
end
