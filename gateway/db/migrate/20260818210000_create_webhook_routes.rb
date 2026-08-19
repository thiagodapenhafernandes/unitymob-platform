# frozen_string_literal: true

class CreateWebhookRoutes < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_routes do |t|
      t.string :provider, null: false, default: "whatsapp"
      t.string :client_key, null: false
      t.string :tenant_name
      t.string :waba_id
      t.string :phone_number_id, null: false
      t.string :target_url, null: false
      t.string :forwarding_secret, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_seen_at
      t.text :last_error

      t.timestamps
    end

    add_index :webhook_routes, %i[provider phone_number_id], unique: true
    add_index :webhook_routes, %i[provider waba_id]
    add_index :webhook_routes, %i[provider active]
  end
end
