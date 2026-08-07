class CreateExternalLeadIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :external_lead_integrations do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.references :distribution_rule, foreign_key: true
      t.references :connected_by_admin_user, foreign_key: { to_table: :admin_users }
      t.boolean :enabled, null: false, default: false
      t.string :status, null: false, default: "disconnected"
      t.text :access_token
      t.string :webhook_token, null: false
      t.string :webhook_url
      t.string :company_id
      t.string :company_name
      t.jsonb :company_payload, null: false, default: {}
      t.jsonb :sellers_payload, null: false, default: []
      t.jsonb :tags_payload, null: false, default: []
      t.jsonb :seller_mappings, null: false, default: {}
      t.string :sync_status, null: false, default: "idle"
      t.string :sync_message
      t.integer :total_count, null: false, default: 0
      t.integer :imported_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :current_page, null: false, default: 0
      t.datetime :last_backfill_at
      t.datetime :last_incremental_sync_at
      t.datetime :last_cursor_at
      t.datetime :last_webhook_at
      t.datetime :subscribed_at
      t.datetime :unsubscribed_at
      t.datetime :deactivated_at
      t.text :last_error_message

      t.timestamps
    end

    add_index :external_lead_integrations, :webhook_token, unique: true

    add_reference :leads, :external_lead_integration, foreign_key: true
    add_column :leads, :external_lead_id, :string
    add_column :leads, :external_internal_id, :bigint
    add_column :leads, :external_last_synced_at, :datetime
    add_index :leads, [:tenant_id, :external_lead_id], unique: true, where: "external_lead_id IS NOT NULL", name: "index_leads_on_tenant_external_lead_id"
    add_index :leads, :external_internal_id
  end
end
