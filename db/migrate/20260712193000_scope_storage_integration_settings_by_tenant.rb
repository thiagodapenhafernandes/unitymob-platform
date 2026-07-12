class ScopeStorageIntegrationSettingsByTenant < ActiveRecord::Migration[7.1]
  def up
    add_reference :storage_integration_settings, :tenant, foreign_key: true, index: { unique: true }

    default_slug = ENV.fetch("DEFAULT_TENANT_SLUG", "default")
    default_tenant_id = select_value(<<~SQL.squish)
      SELECT id FROM tenants
      WHERE slug = #{connection.quote(default_slug)}
      ORDER BY id ASC LIMIT 1
    SQL
    default_tenant_id ||= select_value("SELECT id FROM tenants ORDER BY id ASC LIMIT 1")

    if default_tenant_id
      execute <<~SQL.squish
        UPDATE storage_integration_settings
        SET tenant_id = #{connection.quote(default_tenant_id)}
        WHERE tenant_id IS NULL
      SQL
      change_column_null :storage_integration_settings, :tenant_id, false
      execute <<~SQL.squish
        UPDATE settings
        SET tenant_id = #{connection.quote(default_tenant_id)}
        WHERE tenant_id IS NULL AND key LIKE 'tracking.%'
      SQL
    end

  end

  def down
    remove_reference :storage_integration_settings, :tenant, foreign_key: true
  end
end
