class CreateAutomationWebhookDeliveries < ActiveRecord::Migration[7.1]
  def change
    create_table :automation_webhook_deliveries do |t|
      t.references :automation_event, null: true, foreign_key: true
      t.references :automation_run, null: true, foreign_key: true
      t.references :automation_execution_step, null: true, foreign_key: true
      t.references :lead, null: true, foreign_key: true
      t.string :url, null: false
      t.string :http_method, null: false, default: "post"
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.integer :response_code
      t.jsonb :request_headers, null: false, default: {}
      t.jsonb :request_payload, null: false, default: {}
      t.text :response_body
      t.text :error_message
      t.datetime :sent_at
      t.datetime :responded_at

      t.timestamps
    end

    add_index :automation_webhook_deliveries, :status
    add_index :automation_webhook_deliveries, :created_at
  end
end
