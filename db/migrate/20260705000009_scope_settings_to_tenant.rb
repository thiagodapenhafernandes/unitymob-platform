class ScopeSettingsToTenant < ActiveRecord::Migration[7.1]
  # Setting era key-value GLOBAL: token DWV/Loft/OpenAI, gates e roteamento de
  # lead configurados por uma conta valiam para todas. Passa a aceitar escopo
  # por tenant com FALLBACK: linha do tenant vence; sem ela, vale a global
  # (linhas existentes ficam globais → comportamento atual preservado; cada
  # conta passa a "sombrear" a global quando salvar a própria configuração).
  def up
    unless column_exists?(:settings, :tenant_id)
      add_reference :settings, :tenant, foreign_key: true
    end

    if index_exists?(:settings, :key, name: :index_settings_on_key_unique)
      remove_index :settings, name: :index_settings_on_key_unique
    end

    execute <<~SQL
      CREATE UNIQUE INDEX IF NOT EXISTS idx_settings_global_key_unique
      ON settings (key) WHERE tenant_id IS NULL
    SQL
    execute <<~SQL
      CREATE UNIQUE INDEX IF NOT EXISTS idx_settings_tenant_key_unique
      ON settings (tenant_id, key) WHERE tenant_id IS NOT NULL
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS idx_settings_tenant_key_unique"
    execute "DROP INDEX IF EXISTS idx_settings_global_key_unique"
    execute "DELETE FROM settings WHERE tenant_id IS NOT NULL"
    remove_reference :settings, :tenant, foreign_key: true if column_exists?(:settings, :tenant_id)
    unless index_exists?(:settings, :key, name: :index_settings_on_key_unique)
      add_index :settings, :key, unique: true, name: :index_settings_on_key_unique
    end
  end
end
