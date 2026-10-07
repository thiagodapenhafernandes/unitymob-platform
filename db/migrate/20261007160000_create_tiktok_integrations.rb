class CreateTiktokIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :tiktok_integrations do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.references :admin_user, null: false, foreign_key: true
      t.string :route_key, null: false
      t.text :access_token
      t.jsonb :ad_accounts, null: false, default: []
      t.jsonb :selected_account_ids, null: false, default: []
      t.jsonb :catalog, null: false, default: {}
      t.jsonb :subscriptions, null: false, default: {}
      t.datetime :last_synced_at
      t.datetime :last_lead_received_at
      t.string :last_error
      t.timestamps
    end
    add_index :tiktok_integrations, :route_key, unique: true
    create_table :tiktok_lead_receipts do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead, foreign_key: { on_delete: :nullify }
      t.string :advertiser_id, null: false
      t.string :external_id, null: false
      t.timestamps
    end
    add_index :tiktok_lead_receipts, [:tenant_id, :advertiser_id, :external_id], unique: true, name: "index_tiktok_receipt_identity"
    add_column :distribution_rules, :source_tiktok, :boolean, null: false, default: false
    add_column :distribution_rules, :tiktok_account_ids, :jsonb, null: false, default: []
    add_column :distribution_rules, :tiktok_form_ids, :jsonb, null: false, default: []
  end
end
