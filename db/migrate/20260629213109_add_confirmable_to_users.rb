class AddConfirmableToUsers < ActiveRecord::Migration[8.1]
  def up
    change_table :users do |t|
      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string :unconfirmed_email
    end

    add_index :users, :confirmation_token, unique: true, where: "confirmation_token IS NOT NULL"

    # Backfill: auto-confirma todos los usuarios existentes para que la activación
    # de :confirmable no los bloquee. Datos preexistentes se consideran legítimos
    # porque ya pasaron por el flujo previo de registro sin confirmación.
    execute <<~SQL.squish
      UPDATE users
      SET confirmed_at = COALESCE(created_at, CURRENT_TIMESTAMP)
      WHERE confirmed_at IS NULL
    SQL
  end

  def down
    remove_index :users, :confirmation_token
    remove_columns :users, :confirmation_token, :confirmed_at, :confirmation_sent_at, :unconfirmed_email
  end
end
