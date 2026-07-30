class AddUniqueConstraintsForInvariants < ActiveRecord::Migration[8.1]
  # #108: respaldar en la BD invariantes que hoy solo se sostienen por el flujo.
  # Índices únicos PARCIALES (WHERE) — válidos en SQLite (BD de prod). Si algún
  # día se migra a PostgreSQL, estos siguen siendo soportados (índices parciales).
  def change
    # BR-041: un solo household_admin por FamilyGroup.
    add_index :residencies, :family_group_id,
      unique: true,
      where: "household_admin = 1",
      name: "index_residencies_one_admin_per_family_group"

    # BR-070: una sola vigencia de precio de certificado abierta (effective_to NULL) por junta.
    add_index :certificate_pricings, :neighborhood_association_id,
      unique: true,
      where: "effective_to IS NULL",
      name: "index_certificate_pricings_one_current_per_association"

    # BR-084: una sola vigencia de precio de publicación abierta por junta.
    add_index :listing_pricings, :neighborhood_association_id,
      unique: true,
      where: "effective_to IS NULL",
      name: "index_listing_pricings_one_current_per_association"
  end
end
