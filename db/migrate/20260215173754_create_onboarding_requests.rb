class CreateOnboardingRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :onboarding_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :neighborhood_association, null: false, foreign_key: true
      t.string :status, default: "pending", null: false
      t.text :rejection_reason

      t.timestamps
    end

    # Agregar referencia a OnboardingRequest en las solicitudes hijas
    add_reference :identity_verification_requests, :onboarding_request, foreign_key: true
    add_reference :residence_verification_requests, :onboarding_request, foreign_key: true
  end
end
