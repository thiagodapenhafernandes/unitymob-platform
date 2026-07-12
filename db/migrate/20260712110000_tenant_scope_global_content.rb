class TenantScopeGlobalContent < ActiveRecord::Migration[7.1]
  TABLES = %i[
    captacao_goals landing_pages webhook_settings home_sections home_section_items
    banners marketing_campaigns photography_schedule_blocks seo_settings seo_redirects
  ].freeze

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

    execute <<~SQL
      UPDATE home_sections SET tenant_id = #{connection.quote(owner_id)} WHERE tenant_id IS NULL;
      UPDATE home_section_items items
         SET tenant_id = sections.tenant_id
        FROM home_sections sections
       WHERE items.home_section_id = sections.id AND items.tenant_id IS NULL;
      UPDATE marketing_campaigns campaigns
         SET tenant_id = users.tenant_id
        FROM admin_users users
       WHERE campaigns.admin_user_id = users.id AND campaigns.tenant_id IS NULL AND users.tenant_id IS NOT NULL;
      UPDATE photography_schedule_blocks blocks
         SET tenant_id = users.tenant_id
        FROM admin_users users
       WHERE blocks.created_by_id = users.id AND blocks.tenant_id IS NULL AND users.tenant_id IS NOT NULL;
      UPDATE seo_redirects redirects
         SET tenant_id = users.tenant_id
        FROM admin_users users
       WHERE redirects.created_by_admin_user_id = users.id AND redirects.tenant_id IS NULL AND users.tenant_id IS NOT NULL;
    SQL

    (TABLES - %i[home_section_items]).each do |table|
      execute "UPDATE #{quote_table_name(table)} SET tenant_id = #{connection.quote(owner_id)} WHERE tenant_id IS NULL"
    end
    execute "UPDATE home_section_items SET tenant_id = #{connection.quote(owner_id)} WHERE tenant_id IS NULL"

    TABLES.each { |table| change_column_null table, :tenant_id, false }

    remove_index :landing_pages, :slug if index_exists?(:landing_pages, :slug)
    add_index :landing_pages, %i[tenant_id slug], unique: true
    remove_index :seo_settings, :page_name if index_exists?(:seo_settings, :page_name)
    remove_index :seo_settings, :canonical_key if index_exists?(:seo_settings, :canonical_key)
    add_index :seo_settings, %i[tenant_id page_name], unique: true
    add_index :seo_settings, %i[tenant_id canonical_key], unique: true
  end

  def down
    remove_index :seo_settings, %i[tenant_id canonical_key]
    remove_index :seo_settings, %i[tenant_id page_name]
    add_index :seo_settings, :canonical_key, unique: true
    add_index :seo_settings, :page_name, unique: true
    remove_index :landing_pages, %i[tenant_id slug]
    add_index :landing_pages, :slug, unique: true
    TABLES.reverse_each { |table| remove_reference table, :tenant, foreign_key: true }
  end
end
