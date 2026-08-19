# frozen_string_literal: true

class CreateWebhookEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_events do |t|
      t.references :webhook_route, foreign_key: true
      t.string :provider, null: false, default: "whatsapp"
      t.string :external_id
      t.string :event_type, null: false
      t.string :waba_id
      t.string :phone_number_id
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "received"
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.datetime :received_at, null: false
      t.datetime :forwarded_at

      t.timestamps
    end

    add_index :webhook_events, %i[provider external_id]
    add_index :webhook_events, %i[provider phone_number_id received_at]
    add_index :webhook_events, %i[provider waba_id received_at]
    add_index :webhook_events, %i[status received_at]
  end
end
