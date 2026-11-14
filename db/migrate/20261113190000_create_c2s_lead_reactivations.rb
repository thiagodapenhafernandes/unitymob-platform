class CreateC2sLeadReactivations < ActiveRecord::Migration[7.1]
  def change
    create_table :c2s_lead_reactivations do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :lead, null: false, foreign_key: { on_delete: :cascade }
      t.references :whatsapp_campaign_message, foreign_key: { on_delete: :nullify }, index: false
      t.references :distribution_rule, foreign_key: { on_delete: :nullify }
      t.references :external_lead_integration, foreign_key: { on_delete: :nullify }
      t.string :external_lead_id, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :reactivated_at
      t.datetime :redistributed_at
      t.string :seller_id
      t.string :error_message
      t.timestamps
    end
    add_index :c2s_lead_reactivations, [:tenant_id, :whatsapp_campaign_message_id], unique: true, name: "index_c2s_reactivations_on_tenant_message"
    add_check_constraint :c2s_lead_reactivations, "status IN ('pending', 'reactivating', 'reactivated', 'redistributing', 'completed', 'failed', 'uncertain')", name: "c2s_reactivation_status"
  end
end
