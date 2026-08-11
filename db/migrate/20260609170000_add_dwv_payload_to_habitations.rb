class AddDwvPayloadToHabitations < ActiveRecord::Migration[7.1]
  def up
    add_column :habitations, :dwv_payload, :jsonb, default: {}, null: false unless column_exists?(:habitations, :dwv_payload)
    add_index :habitations, :dwv_payload, using: :gin unless index_exists?(:habitations, :dwv_payload)

    return unless table_exists?(:settings)

    execute(<<~SQL)
      UPDATE settings
      SET value = '100',
          description = 'Máximo de páginas da sincronização DWV',
          updated_at = CURRENT_TIMESTAMP
      WHERE key = 'dwv_sync_max_pages'
        AND COALESCE(NULLIF(value, '')::integer, 0) <= 10
    SQL

    execute(<<~SQL)
      INSERT INTO settings (key, value, description, created_at, updated_at)
      SELECT 'dwv_sync_max_pages', '100', 'Máximo de páginas da sincronização DWV', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      WHERE NOT EXISTS (
        SELECT 1 FROM settings WHERE key = 'dwv_sync_max_pages'
      )
    SQL
  end

  def down
    remove_index :habitations, :dwv_payload if index_exists?(:habitations, :dwv_payload)
    remove_column :habitations, :dwv_payload if column_exists?(:habitations, :dwv_payload)
  end
end
