class CreateNotificationTemplateSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :notification_template_settings do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :whatsapp_template, null: true, foreign_key: true
      t.string :channel, null: false, default: "whatsapp"
      t.string :purpose, null: false
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :notification_template_settings,
              [:tenant_id, :channel, :purpose],
              unique: true,
              name: "idx_notification_template_settings_unique_purpose"
    add_index :notification_template_settings, [:tenant_id, :active]
  end
end
