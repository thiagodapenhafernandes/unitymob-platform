class AddActionToLeadPipelineStageAutomations < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_pipeline_stage_automations, :action_type, :string, null: false, default: "move_stage"
    add_column :lead_pipeline_stage_automations, :action_config, :jsonb, null: false, default: {}
    add_index :lead_pipeline_stage_automations,
              [:tenant_id, :action_type],
              name: "idx_stage_automations_on_tenant_action_type"
  end
end
