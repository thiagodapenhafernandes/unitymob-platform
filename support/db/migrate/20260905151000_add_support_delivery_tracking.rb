class AddSupportDeliveryTracking < ActiveRecord::Migration[7.1]
  def change
    add_column :support_deliveries, :failed_at, :datetime
    add_column :support_messages, :notification_pending, :boolean, default: false, null: false
    add_column :support_messages, :notified_at, :datetime
    add_index :support_messages, :notification_pending, where: "notification_pending = true"
  end
end
