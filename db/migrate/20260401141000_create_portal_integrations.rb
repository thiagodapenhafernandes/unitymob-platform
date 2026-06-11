class CreatePortalIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_integrations do |t|
      t.string :portal, null: false
      t.boolean :enabled, null: false, default: false
      t.string :allowed_statuses, array: true, default: [], null: false
      t.string :allowed_business_types, array: true, default: %w[venda aluguel], null: false
      t.boolean :require_exibir_no_site, null: false, default: true
      t.string :feed_token
      t.string :account_id
      t.string :publisher_id
      t.string :webhook_secret
      t.string :operational_status, null: false, default: "idle"
      t.jsonb :settings, null: false, default: {}
      t.datetime :last_feed_at
      t.datetime :last_webhook_at

      t.timestamps
    end

    add_index :portal_integrations, :portal, unique: true
    add_index :portal_integrations, :enabled
  end
end
