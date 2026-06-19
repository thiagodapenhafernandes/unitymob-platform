class CreateWhatsappMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_messages do |t|
      t.references :whatsapp_conversation, null: false, foreign_key: true
      t.references :admin_user, null: true, foreign_key: true
      t.string :direction, null: false # inbound | outbound
      t.string :wa_message_id
      t.string :msg_type, null: false, default: "text"
      t.text :body
      t.string :media_url
      t.string :status, null: false, default: "pending"
      t.string :error_message
      t.string :template_name
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at

      t.timestamps
    end

    add_index :whatsapp_messages, :wa_message_id
    add_index :whatsapp_messages, [:whatsapp_conversation_id, :created_at]
  end
end
