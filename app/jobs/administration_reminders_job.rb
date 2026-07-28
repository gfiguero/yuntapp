class AdministrationRemindersJob < ApplicationJob
  queue_as :default

  # BR-133: digest diario al staff (superadmin) mientras existan solicitudes de
  # administración en estado `pending` sin revisar. Se ejecuta a diario vía
  # config/recurring.yml.
  def perform
    pending = AdministrationRequest.pending.to_a
    return if pending.empty?

    User.where(superadmin: true).find_each do |staff|
      AdministrationRequestMailer.staff_digest(staff, pending).deliver_later if staff.email.present?
    end
  end
end
