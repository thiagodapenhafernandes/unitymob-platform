class AddQueuedDeliveries < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!
  def change
    create_table :delivery_destinations do |t|
      t.string :host, null: false
      t.datetime :available_at, null: false
    end
    add_index :delivery_destinations, :host, unique: true
    add_reference :webhook_events, :delivery_destination, index: false
    add_foreign_key :webhook_events, :delivery_destinations, validate: false
    add_index :webhook_events, :delivery_destination_id, algorithm: :concurrently
    add_column :webhook_events, :delivery_key, :string
    add_column :webhook_events, :queued_at, :datetime
    add_column :webhook_events, :queue_finished_at, :datetime
    add_index :webhook_events, :delivery_key, unique: true, algorithm: :concurrently
    add_index :webhook_events, [:provider, :external_id], name: 'index_webhook_events_receipt_identity', algorithm: :concurrently
    add_index :webhook_events, [:delivery_destination_id, :id],
      where: 'queued_at IS NOT NULL AND queue_finished_at IS NULL', name: 'index_pending_queued_deliveries', algorithm: :concurrently
  end
end
