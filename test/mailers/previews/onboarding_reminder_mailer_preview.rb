# Preview all emails at http://localhost:3000/rails/mailers/onboarding_reminder_mailer
class OnboardingReminderMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/onboarding_reminder_mailer/pending_digest
  def pending_digest
    admin = User.find_by(admin: true)
    requests = OnboardingRequest.pending.where(neighborhood_association_id: admin&.neighborhood_association_id)
    OnboardingReminderMailer.pending_digest(admin, requests)
  end
end
