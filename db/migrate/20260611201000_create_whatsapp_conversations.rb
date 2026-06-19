class CreateWhatsappConversations < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_conversations do |t|
      t.references :lead, null: true, foreign_key: true
      t.references :assigned_admin_user, null: true, foreign_key: { to_table: :admin_users }
      t.string :contact_phone, null: false
      t.string :contact_name
      t.datetime :last_message_at
      t.string :last_message_preview
      t.integer :unread_count, null: false, default: 0
      t.string :status, null: false, default: "open"

      t.timestamps
    end

    add_index :whatsapp_conversations, :contact_phone, unique: true
    add_index :whatsapp_conversations, :last_message_at
  end
end
