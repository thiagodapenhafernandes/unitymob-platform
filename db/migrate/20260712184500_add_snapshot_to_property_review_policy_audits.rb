class AddSnapshotToPropertyReviewPolicyAudits < ActiveRecord::Migration[7.1]
  def change
    add_column :property_review_policy_audit_logs, :policy_snapshot, :jsonb, null: false, default: {}
  end
end
