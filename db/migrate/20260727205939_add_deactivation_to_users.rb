class AddDeactivationToUsers < ActiveRecord::Migration[8.1]
  def change
    # BR-100: las cuentas nunca se borran; se desactivan (auto-servicio, reversible por
    # el usuario vía correo) o se bloquean (por superadmin, no reversible por el usuario).
    add_column :users, :deactivated_at, :datetime
    add_column :users, :blocked_at, :datetime
    add_column :users, :block_reason, :string
    add_reference :users, :blocked_by, foreign_key: {to_table: :users}, null: true
  end
end
