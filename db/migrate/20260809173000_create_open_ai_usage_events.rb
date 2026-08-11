class CreateOpenAiUsageEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :open_ai_usage_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, foreign_key: true
      t.string :feature, null: false
      t.string :model
      t.string :status, null: false, default: "succeeded"
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :estimated_cost_cents, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :open_ai_usage_events, [:tenant_id, :feature, :created_at]
    add_index :open_ai_usage_events, [:tenant_id, :created_at]
  end
end
