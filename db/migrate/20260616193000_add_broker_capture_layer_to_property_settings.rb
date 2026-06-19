class AddBrokerCaptureLayerToPropertySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :property_settings, :broker_capture_layer_enabled, :boolean, null: false, default: true
    add_column :property_settings, :required_broker_intake_checks, :text, array: true, default: [], null: false
    add_column :property_settings, :returnable_intake_edit_sections, :text, array: true, default: [], null: false
    add_reference :property_settings, :broker_capture_fallback_admin_user, null: true, foreign_key: { to_table: :admin_users }

    add_index :property_settings, :broker_capture_layer_enabled
  end
end
