class CreatePropertyReviewPolicies < ActiveRecord::Migration[7.1]
  def change
    create_table :property_review_policies do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :property_setting, null: false, foreign_key: true
      t.string :registration_type, null: false
      t.string :category
      t.string :modality
      t.boolean :active, null: false, default: true
      t.integer :version, null: false, default: 1
      t.boolean :broker_capture_layer_enabled, null: false, default: true
      t.text :required_broker_intake_checks, array: true, null: false, default: []
      t.text :returnable_intake_edit_sections, array: true, null: false, default: []
      t.boolean :notify_internal_review_events, null: false, default: true
      t.boolean :notify_email_review_events, null: false, default: false
      t.text :review_notification_emails

      t.timestamps
    end

    add_index :property_review_policies, [:tenant_id, :registration_type]
    add_index :property_review_policies, [:tenant_id, :registration_type, :category]

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          CREATE UNIQUE INDEX idx_property_review_policies_context
          ON property_review_policies (
            tenant_id,
            registration_type,
            COALESCE(category, ''),
            COALESCE(modality, '')
          )
          WHERE active = TRUE
        SQL
      end

      dir.down do
        execute "DROP INDEX IF EXISTS idx_property_review_policies_context"
      end
    end
  end
end
