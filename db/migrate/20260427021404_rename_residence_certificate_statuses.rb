class RenameResidenceCertificateStatuses < ActiveRecord::Migration[8.1]
  def up
    ResidenceCertificate.where(status: "pending").update_all(status: "pending_payment")
    ResidenceCertificate.where(status: "approved").update_all(status: "paid")
    ResidenceCertificate.where(status: "rejected").update_all(status: "pending_payment")
    change_column_default :residence_certificates, :status, from: "pending", to: "pending_payment"
  end

  def down
    change_column_default :residence_certificates, :status, from: "pending_payment", to: "pending"
    ResidenceCertificate.where(status: "pending_payment").update_all(status: "pending")
    ResidenceCertificate.where(status: "paid").update_all(status: "approved")
  end
end
