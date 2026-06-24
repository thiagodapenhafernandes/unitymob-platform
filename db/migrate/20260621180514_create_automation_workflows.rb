class CreateAutomationWorkflows < ActiveRecord::Migration[7.1]
  def change
    create_table :automation_workflows do |t|
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.bigint :active_version_id
      t.references :created_by, null: true, foreign_key: { to_table: :admin_users }
      t.datetime :last_activated_at

      t.timestamps
    end

    add_index :automation_workflows, :status
    add_index :automation_workflows, :active_version_id

    create_table :automation_workflow_versions do |t|
      t.references :automation_workflow, null: false, foreign_key: true
      t.integer :version_number, null: false
      t.string :status, null: false, default: "draft"
      t.jsonb :definition, null: false, default: {}
      t.jsonb :validation_snapshot, null: false, default: {}
      t.references :created_by, null: true, foreign_key: { to_table: :admin_users }
      t.references :published_by, null: true, foreign_key: { to_table: :admin_users }
      t.datetime :published_at

      t.timestamps
    end

    add_index :automation_workflow_versions,
              [:automation_workflow_id, :version_number],
              unique: true,
              name: "idx_automation_workflow_versions_unique_number"
    add_index :automation_workflow_versions,
              [:automation_workflow_id, :status],
              name: "idx_automation_workflow_versions_on_workflow_status"

    add_foreign_key :automation_workflows,
                    :automation_workflow_versions,
                    column: :active_version_id

    create_table :automation_executions do |t|
      t.references :automation_workflow, null: false, foreign_key: true
      t.references :automation_workflow_version, null: false, foreign_key: true
      t.references :lead, null: true, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :current_node_id
      t.string :idempotency_key
      t.jsonb :context, null: false, default: {}
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :failed_at
      t.text :error_message

      t.timestamps
    end

    add_index :automation_executions, :status
    add_index :automation_executions, :idempotency_key, unique: true
    add_index :automation_executions,
              [:automation_workflow_id, :lead_id, :status],
              name: "idx_automation_executions_workflow_lead_status"

    create_table :automation_execution_steps do |t|
      t.references :automation_execution, null: false, foreign_key: true
      t.string :node_id, null: false
      t.string :node_type, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :scheduled_for
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :input, null: false, default: {}
      t.jsonb :output, null: false, default: {}
      t.text :error_message

      t.timestamps
    end

    add_index :automation_execution_steps,
              [:automation_execution_id, :node_id],
              name: "idx_automation_execution_steps_on_execution_node"
    add_index :automation_execution_steps, :status
    add_index :automation_execution_steps, :scheduled_for
  end
end
