class CreateAutomationRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :automation_runs do |t|
      t.references :automation_rule, null: false, foreign_key: true
      t.references :lead, null: true, foreign_key: true
      t.string :status, null: false, default: "executed"
      t.datetime :scheduled_at
      t.datetime :executed_at
      t.jsonb :result, null: false, default: {}

      t.timestamps
    end

    add_index :automation_runs, [:automation_rule_id, :lead_id]
  end
end
