class CreateAdministrationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :administration_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :neighborhood_association, foreign_key: true # junta existente (opcional)
      t.references :region, foreign_key: true
      t.references :commune, foreign_key: true
      t.string :proposed_association_name # junta nueva (opcional)
      t.string :organization_rut          # RUT de la organización (obligatorio al enviar)
      t.string :position                  # cargo de directiva
      t.string :first_name
      t.string :last_name
      t.string :run
      t.string :phone
      t.string :status, null: false, default: "draft"
      t.references :reviewed_by, foreign_key: {to_table: :users}
      t.datetime :reviewed_at
      t.text :rejection_reason

      t.timestamps
    end

    add_index :administration_requests, :status
  end
end
