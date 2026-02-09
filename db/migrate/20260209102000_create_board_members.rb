class CreateBoardMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :board_members do |t|
      t.references :neighborhood_association, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.string :position, null: false
      t.date :start_date
      t.date :end_date
      t.boolean :active, default: true
      t.timestamps
    end
  end
end
