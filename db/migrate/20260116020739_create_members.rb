class CreateMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :members do |t|
      t.string :first_name
      t.string :last_name
      t.string :run
      t.string :phone
      t.string :email
      t.references :household_unit, null: false, foreign_key: true

      t.timestamps
    end
  end
end
