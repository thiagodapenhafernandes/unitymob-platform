class CreateInboundWebhookTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :inbound_webhook_tokens do |t|
      t.references :admin_user, null: false, foreign_key: true, index: { unique: true }
      t.string :token, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :last_received_at

      t.timestamps
    end

    add_index :inbound_webhook_tokens, :token, unique: true
  end
end
