class AddIntakeReviewPolicySnapshotToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :intake_review_policy_version, :integer unless column_exists?(:habitations, :intake_review_policy_version)
    add_column :habitations, :intake_review_policy_snapshot, :jsonb, default: {}, null: false unless column_exists?(:habitations, :intake_review_policy_snapshot)

    add_index :habitations,
              [:tenant_id, :intake_status, :intake_review_policy_version],
              name: "index_habitations_on_tenant_intake_policy_version",
              if_not_exists: true
  end
end
