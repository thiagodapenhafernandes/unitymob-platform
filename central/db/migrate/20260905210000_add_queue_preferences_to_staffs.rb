class AddQueuePreferencesToStaffs < ActiveRecord::Migration[7.1]
  def change
    add_column :staffs, :queue_preferences, :jsonb, null:false, default:{}
  end
end
