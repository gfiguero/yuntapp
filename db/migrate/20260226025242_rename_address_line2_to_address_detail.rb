class RenameAddressLine2ToAddressDetail < ActiveRecord::Migration[8.1]
  def change
    rename_column :household_units, :address_line_2, :address_detail
    rename_column :residence_verification_requests, :address_line_2, :address_detail
    rename_column :verified_residences, :address_line_2, :address_detail
  end
end
