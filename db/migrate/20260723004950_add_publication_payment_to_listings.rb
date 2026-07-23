class AddPublicationPaymentToListings < ActiveRecord::Migration[8.1]
  class MigrationListing < ActiveRecord::Base
    self.table_name = "listings"
  end

  def change
    add_column :listings, :publication_status, :string, null: false, default: "pending_payment"
    add_column :listings, :amount, :integer
    add_column :listings, :platform_fee, :integer
    add_column :listings, :payment_id, :string
    add_column :listings, :paid_at, :datetime
    add_column :listings, :published_until, :date
    add_column :listings, :neighborhood_association_id, :integer

    add_index :listings, :payment_id, unique: true
    add_index :listings, :publication_status
    add_index :listings, :neighborhood_association_id

    # Publicaciones existentes creadas antes del cobro por publicación:
    # se les otorga una vigencia de gracia de 30 días desde el deploy para
    # no despublicarlas retroactivamente. Las inactivas quedan
    # pending_payment como cualquier publicación nueva.
    reversible do |dir|
      dir.up do
        MigrationListing.where(active: true).update_all(
          publication_status: "published",
          published_until: 30.days.from_now.to_date
        )
      end
    end
  end
end
