class OnboardingRemindersJob < ApplicationJob
  queue_as :default

  # BR-050: recorre las juntas con solicitudes de onboarding en `pending` y
  # envía un digest a cada admin de la junta. Multi-tenant (BR-007/BR-052):
  # cada admin solo recibe el resumen de su propia junta. Se ejecuta a diario
  # vía config/recurring.yml.
  def perform
    pending_by_association = OnboardingRequest.pending
      .where.not(neighborhood_association_id: nil)
      .group_by(&:neighborhood_association_id)

    pending_by_association.each do |association_id, requests|
      admins = User.where(admin: true, neighborhood_association_id: association_id)
      next if admins.empty?

      admins.find_each do |admin|
        OnboardingReminderMailer.pending_digest(admin, requests).deliver_later
      end
    end
  end
end
