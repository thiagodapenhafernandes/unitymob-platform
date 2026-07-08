class CreateGoogleCalendarIntegrationSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :google_calendar_integration_settings do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :calendar_id
      t.integer :default_duration_minutes, null: false, default: 60
      t.text :service_account_json
      t.datetime :last_synced_at

      t.timestamps
    end
  end
end
