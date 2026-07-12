class AddGovernanceToPropertyReviewWorkflow < ActiveRecord::Migration[7.1]
  def change
    add_column :property_settings, :review_policy_version, :integer, null: false, default: 1

    create_table :property_review_policy_audit_logs do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :property_setting, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.integer :version, null: false
      t.jsonb :changeset, null: false, default: {}
      t.jsonb :impact_snapshot, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :property_review_policy_audit_logs, [:tenant_id, :created_at], name: "idx_review_policy_audits_tenant_created"
    add_index :property_review_policy_audit_logs, [:property_setting_id, :version], unique: true, name: "idx_review_policy_audits_setting_version"
  end
end
