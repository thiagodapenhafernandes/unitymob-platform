class CreateLeadPipelineStageAutomations < ActiveRecord::Migration[7.1]
  def up
    create_table :lead_pipeline_stage_automations do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead_pipeline_stage, null: false, foreign_key: true, index: { name: "idx_stage_automations_on_stage" }
      t.references :auto_advance_to_stage,
                   foreign_key: { to_table: :lead_pipeline_stages, on_delete: :nullify },
                   index: { name: "idx_stage_automations_on_destination_stage" }
      t.string :trigger, null: false, default: "stage_duration"
      t.integer :after_amount, null: false
      t.string :after_unit, null: false, default: "days"
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :lead_pipeline_stage_automations,
              [:tenant_id, :lead_pipeline_stage_id, :active, :position],
              name: "idx_stage_automations_on_tenant_stage_active"
  end

  def down
    remove_index :lead_pipeline_stage_automations,
                 name: "idx_stage_automations_on_tenant_stage_active"
    drop_table :lead_pipeline_stage_automations
  end
end
