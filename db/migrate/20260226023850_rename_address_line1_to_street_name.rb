class RenameAddressLine1ToStreetName < ActiveRecord::Migration[8.1]
  def change
    rename_column :household_units, :address_line_1, :street_name
    rename_column :residence_verification_requests, :address_line_1, :street_name
    rename_column :verified_residences, :address_line_1, :street_name
  end
end
