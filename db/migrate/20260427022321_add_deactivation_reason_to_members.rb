class AddDeactivationReasonToMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :members, :deactivation_reason, :text
  end
end
