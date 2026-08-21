class CreateLeadPipelineStageAutomationExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_pipeline_stage_automation_executions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead_pipeline_stage_automation,
                   null: false,
                   foreign_key: true,
                   index: { name: "idx_stage_automation_executions_on_automation" }
      t.references :lead,
                   null: false,
                   foreign_key: true,
                   index: { name: "idx_stage_automation_executions_on_lead" }
      t.references :lead_pipeline_stage,
                   null: false,
                   foreign_key: true,
                   index: { name: "idx_stage_automation_executions_on_stage" }
      t.string :action_type, null: false
      t.string :trigger, null: false
      t.string :status, null: false, default: "started"
      t.datetime :stage_entered_at, null: false
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :error_class
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :lead_pipeline_stage_automation_executions,
              [:tenant_id, :lead_pipeline_stage_automation_id, :lead_id, :stage_entered_at],
              unique: true,
              name: "idx_stage_automation_executions_unique_run"
    add_index :lead_pipeline_stage_automation_executions,
              [:tenant_id, :status, :action_type, :created_at],
              name: "idx_stage_automation_executions_status_action"
  end
end
