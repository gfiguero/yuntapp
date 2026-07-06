require "test_helper"

class OnboardingRemindersJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  # manios_de_buin tiene 2 solicitudes pending (karass, karax) y 1 admin (selendis).
  test "sends one digest to the admin of a junta with pending requests" do
    assert_emails 1 do
      perform_enqueued_jobs do
        OnboardingRemindersJob.perform_now
      end
    end

    assert_includes ActionMailer::Base.deliveries.last.to, users(:selendis).email
  end

  test "does not send anything when there are no pending requests" do
    OnboardingRequest.pending.update_all(status: "approved")

    assert_emails 0 do
      perform_enqueued_jobs do
        OnboardingRemindersJob.perform_now
      end
    end
  end

  test "sends to every admin of the junta" do
    # Segundo admin de la misma junta.
    User.create!(
      email: "second_admin@daelaam.io",
      password: "honorandduty",
      admin: true,
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      confirmed_at: Time.current
    )

    assert_emails 2 do
      perform_enqueued_jobs do
        OnboardingRemindersJob.perform_now
      end
    end
  end

  test "skips juntas that have pending requests but no admins" do
    # Mueve un pending a una junta sin admins: no debe generar correo para ella.
    orphan_assoc = neighborhood_associations(:association_0)
    assert_nil User.find_by(admin: true, neighborhood_association: orphan_assoc)

    onboarding_requests(:karax_pending).update!(neighborhood_association: orphan_assoc)

    # Solo manios_de_buin (con admin y 1 pending restante) genera correo.
    assert_emails 1 do
      perform_enqueued_jobs do
        OnboardingRemindersJob.perform_now
      end
    end
  end
end
