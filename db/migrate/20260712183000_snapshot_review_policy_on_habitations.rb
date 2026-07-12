class SnapshotReviewPolicyOnHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :intake_review_policy_version, :integer
    add_column :habitations, :intake_review_policy_snapshot, :jsonb, null: false, default: {}
    add_index :habitations, [:tenant_id, :intake_review_policy_version], name: "idx_habitations_tenant_review_policy_version"
  end
end
