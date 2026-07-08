class RepairDwvApiDefaultsAndRecurringTasks < ActiveRecord::Migration[7.1]
  CANONICAL_BASE_URL = "https://agencies.dwvapp.com.br"
  DOCUMENTATION_BASE_URL = "https://api.dwvapp.com.br"

  def up
    repair_dwv_base_url!
    repair_dwv_recurring_tasks! if table_exists?(:solid_queue_recurring_tasks)
  end

  def down
    # Intencionalmente irreversível: a migração repara configuração operacional
    # e tarefas recorrentes para acompanhar o código atual.
  end

  private

  def repair_dwv_base_url!
    return unless table_exists?(:settings)

    quoted_canonical_base_url = quote(CANONICAL_BASE_URL)
    quoted_now = quote(Time.current)

    execute(<<~SQL.squish)
      UPDATE settings
      SET value = #{quoted_canonical_base_url},
          updated_at = #{quoted_now}
      WHERE key = 'dwv_base_url'
        AND (value IS NULL OR value = '' OR value IN (#{quote(CANONICAL_BASE_URL)}, #{quote(DOCUMENTATION_BASE_URL)}))
    SQL

    return if select_value("SELECT 1 FROM settings WHERE key = 'dwv_base_url' AND tenant_id IS NULL LIMIT 1").present?

    columns = connection.columns(:settings).map(&:name)
    attrs = {
      key: "dwv_base_url",
      value: CANONICAL_BASE_URL,
      created_at: Time.current,
      updated_at: Time.current
    }
    attrs[:description] = "URL base da API DWV" if columns.include?("description")
    attrs[:tenant_id] = nil if columns.include?("tenant_id")
    insert_setting!(attrs)
  end

  def repair_dwv_recurring_tasks!
    quoted_now = quote(Time.current)

    execute(<<~SQL.squish)
      UPDATE solid_queue_recurring_tasks
      SET class_name = 'DwvSyncAllTenantsJob',
          arguments = '[{"mode":"full","_aj_symbol_keys":["mode"]}]',
          queue_name = 'dwv',
          updated_at = #{quoted_now}
      WHERE key = 'dwv_daily_sync'
    SQL

    execute(<<~SQL.squish)
      UPDATE solid_queue_recurring_tasks
      SET class_name = 'DwvSyncAllTenantsJob',
          arguments = '[{"mode":"incremental","_aj_symbol_keys":["mode"]}]',
          queue_name = 'dwv',
          updated_at = #{quoted_now}
      WHERE key = 'dwv_incremental_sync'
    SQL
  end

  def insert_setting!(attrs)
    keys = attrs.keys
    execute(<<~SQL.squish)
      INSERT INTO settings (#{keys.map { |key| quote_column_name(key) }.join(", ")})
      VALUES (#{keys.map { |key| quote(attrs[key]) }.join(", ")})
    SQL
  end
end
