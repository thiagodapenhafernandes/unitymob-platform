class AddUsageFlagsToWhatsappSenderNumbers < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_sender_numbers, :use_for_notifications, :boolean, null: false, default: false

    add_index :whatsapp_sender_numbers, [:tenant_id, :active, :use_for_notifications],
              name: "idx_wa_sender_numbers_notification_usage"
    add_index :whatsapp_sender_numbers, :tenant_id,
              unique: true,
              where: "active = TRUE AND use_for_notifications = TRUE",
              name: "idx_wa_sender_numbers_one_notification"
  end
end
