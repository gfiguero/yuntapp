class AddResidenceVerificationRequestToHouseholdUnits < ActiveRecord::Migration[8.1]
  def change
    add_reference :household_units, :residence_verification_request, null: true, foreign_key: true
  end
end
