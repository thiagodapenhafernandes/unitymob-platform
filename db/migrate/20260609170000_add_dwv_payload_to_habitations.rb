class AddDwvPayloadToHabitations < ActiveRecord::Migration[7.1]
  def up
    add_column :habitations, :dwv_payload, :jsonb, default: {}, null: false unless column_exists?(:habitations, :dwv_payload)
    add_index :habitations, :dwv_payload, using: :gin unless index_exists?(:habitations, :dwv_payload)

    return unless table_exists?(:settings)

    setting = Setting.find_or_initialize_by(key: "dwv_sync_max_pages")
    if setting.value.to_i <= 10
      setting.value = "100"
      setting.description = "Máximo de páginas da sincronização DWV"
      setting.save!
    end
  end

  def down
    remove_index :habitations, :dwv_payload if index_exists?(:habitations, :dwv_payload)
    remove_column :habitations, :dwv_payload if column_exists?(:habitations, :dwv_payload)
  end
end
