class AddUniqueIndexToSettingsKey < ActiveRecord::Migration[7.1]
  INDEX_NAME = "index_settings_on_key_unique".freeze

  def up
    deduplicate_settings_keys!

    add_index :settings, :key, unique: true, name: INDEX_NAME unless index_exists?(:settings, :key, unique: true, name: INDEX_NAME)
  end

  def down
    remove_index :settings, name: INDEX_NAME if index_exists?(:settings, name: INDEX_NAME)
  end

  private

  def deduplicate_settings_keys!
    execute <<~SQL
      DELETE FROM settings older
      USING settings newer
      WHERE older.key IS NOT NULL
        AND newer.key IS NOT NULL
        AND older.key = newer.key
        AND older.id < newer.id;
    SQL
  end
end
