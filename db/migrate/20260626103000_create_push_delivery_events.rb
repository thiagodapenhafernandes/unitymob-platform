class CreatePushDeliveryEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :push_delivery_events do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.references :push_subscription, foreign_key: true
      t.references :lead, foreign_key: true
      t.string :event_type, null: false
      t.string :tag
      t.string :endpoint_host
      t.string :endpoint_sha256
      t.text :user_agent
      t.string :provider_status
      t.string :error_class
      t.text :error_message
      t.string :urgency
      t.integer :ttl
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :push_delivery_events, [:tag, :event_type]
    add_index :push_delivery_events, [:admin_user_id, :created_at]
    add_index :push_delivery_events, [:lead_id, :created_at]
    add_index :push_delivery_events, :endpoint_sha256
  end
end
