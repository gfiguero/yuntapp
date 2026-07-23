class AddSubscriptionToListings < ActiveRecord::Migration[8.1]
  def change
    add_column :listings, :preapproval_id, :string
    add_column :listings, :subscription_status, :string

    add_index :listings, :preapproval_id, unique: true
  end
end
