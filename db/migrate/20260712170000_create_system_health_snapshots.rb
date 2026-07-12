class CreateSystemHealthSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :system_health_snapshots do |t|
      t.references :tenant, foreign_key: true
      t.string :status, null: false
      t.string :source, null: false, default: "platform"
      t.jsonb :metrics, null: false, default: {}
      t.datetime :collected_at, null: false
      t.timestamps
    end

    add_index :system_health_snapshots, [:tenant_id, :collected_at]
    add_index :system_health_snapshots, [:status, :collected_at]
  end
end
