class CreateLinkedinIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :linkedin_integrations do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.references :admin_user, null: false, foreign_key: true
      t.text :access_token
      t.datetime :token_expires_at
      t.jsonb :ad_accounts, null: false, default: []
      t.jsonb :selected_account_ids, null: false, default: []
      t.jsonb :account_cursors, null: false, default: {}
      t.jsonb :catalog, null: false, default: {}
      t.datetime :catalog_synced_at
      t.datetime :last_synced_at
      t.datetime :last_lead_received_at
      t.string :last_error
      t.timestamps
    end
    create_table :linkedin_lead_receipts do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead, foreign_key: { on_delete: :nullify }
      t.string :response_id, null: false
      t.timestamps
    end
    add_index :linkedin_lead_receipts, [:tenant_id, :response_id], unique: true
    add_column :distribution_rules, :source_linkedin, :boolean, null: false, default: false
    add_column :distribution_rules, :linkedin_campaign_ids, :jsonb, null: false, default: []
    add_column :distribution_rules, :linkedin_form_ids, :jsonb, null: false, default: []
  end
end
