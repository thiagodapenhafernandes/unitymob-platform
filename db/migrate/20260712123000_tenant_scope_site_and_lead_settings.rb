class TenantScopeSiteAndLeadSettings < ActiveRecord::Migration[7.1]
  TABLES = %i[layout_settings home_settings footer_settings contact_settings lead_settings].freeze

  def up
    TABLES.each { |table| add_reference table, :tenant, foreign_key: true, index: true, null: true }

    owner_id = select_value("SELECT id FROM tenants WHERE slug = 'saluteimoveis' ORDER BY id LIMIT 1") ||
               select_value("SELECT id FROM tenants ORDER BY id LIMIT 1")
    if owner_id.blank?
      execute <<~SQL
        INSERT INTO tenants (name, slug, active, created_at, updated_at)
        VALUES ('Conta principal', 'default', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      owner_id = select_value("SELECT id FROM tenants WHERE slug = 'default' ORDER BY id LIMIT 1")
    end

    TABLES.each do |table|
      execute "UPDATE #{quote_table_name(table)} SET tenant_id = #{connection.quote(owner_id)} WHERE tenant_id IS NULL"
      change_column_null table, :tenant_id, false
      add_index table, :tenant_id, unique: true, name: "index_#{table}_on_unique_tenant_id"
    end
  end

  def down
    TABLES.reverse_each do |table|
      remove_index table, name: "index_#{table}_on_unique_tenant_id"
      remove_reference table, :tenant, foreign_key: true
    end
  end
end
