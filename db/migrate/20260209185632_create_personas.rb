class CreatePersonas < ActiveRecord::Migration[8.1]
  def change
    create_table :personas do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :run, null: false
      t.string :phone
      t.string :email
      t.string :verification_status, null: false, default: "pending"

      t.timestamps
    end

    add_index :personas, :run, unique: true
    add_index :personas, :verification_status
  end
end
