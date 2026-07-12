class CreateSystemHealthSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :system_health_settings do |t|
      t.decimal :memory_available_warning_percent, null: false, default: 15, precision: 5, scale: 2
      t.decimal :memory_available_critical_percent, null: false, default: 8, precision: 5, scale: 2
      t.decimal :disk_warning_percent, null: false, default: 80, precision: 5, scale: 2
      t.decimal :disk_critical_percent, null: false, default: 90, precision: 5, scale: 2
      t.integer :swap_warning_mb, null: false, default: 512
      t.integer :http_warning_ms, null: false, default: 1500
      t.integer :http_critical_ms, null: false, default: 4000
      t.integer :application_errors_warning, null: false, default: 5
      t.integer :application_errors_critical, null: false, default: 20
      t.integer :integration_failures_critical, null: false, default: 3
      t.timestamps
    end
  end
end
