class CreateLeadPipelineStagePoliciesAndTransitions < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_pipeline_stage_policies do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead_pipeline_stage, null: false, foreign_key: true, index: { name: "idx_stage_policies_on_stage" }
      t.jsonb :visible_to_roles, null: false, default: []
      t.boolean :divergence_queue_enabled, null: false, default: false
      t.integer :future_activity_limit_days
      t.boolean :qualification_enabled, null: false, default: false
      t.jsonb :qualification_options, null: false, default: []
      t.jsonb :allowed_archive_reason_ids, null: false, default: []
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :lead_pipeline_stage_policies,
              [:tenant_id, :lead_pipeline_stage_id],
              unique: true,
              name: "idx_stage_policies_on_tenant_stage"

    create_table :lead_pipeline_stage_transitions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead_pipeline_stage, null: false, foreign_key: true, index: { name: "idx_stage_transitions_on_stage" }
      t.references :next_stage,
                   null: false,
                   foreign_key: { to_table: :lead_pipeline_stages },
                   index: { name: "idx_stage_transitions_on_next_stage" }
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :lead_pipeline_stage_transitions,
              [:tenant_id, :lead_pipeline_stage_id, :next_stage_id],
              unique: true,
              name: "idx_stage_transitions_on_unique_next"
  end
end
