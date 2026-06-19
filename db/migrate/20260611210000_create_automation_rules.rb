class CreateAutomationRules < ActiveRecord::Migration[7.1]
  def change
    create_table :automation_rules do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.string :trigger_event, null: false
      t.jsonb :conditions, null: false, default: {}
      t.jsonb :actions, null: false, default: []
      t.integer :position, null: false, default: 0
      t.datetime :last_run_at
      t.integer :runs_count, null: false, default: 0

      t.timestamps
    end

    add_index :automation_rules, [:active, :trigger_event]
  end
end
