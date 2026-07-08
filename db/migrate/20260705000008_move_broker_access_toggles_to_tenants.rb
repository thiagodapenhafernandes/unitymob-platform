class MoveBrokerAccessTogglesToTenants < ActiveRecord::Migration[7.1]
  # Os toggles "corretor só loga por IP permitido / aparelho aprovado" viviam
  # no Setting (key-value GLOBAL): o dono de uma conta ligava e valia para
  # TODAS. Viram colunas do tenant (mesmo padrão do require_two_factor).
  # Backfill copia o valor global atual para todas as contas — comportamento
  # de hoje preservado; daí em diante cada conta decide o seu.
  def up
    unless column_exists?(:tenants, :enforce_broker_ip_allowlist)
      add_column :tenants, :enforce_broker_ip_allowlist, :boolean, null: false, default: false
    end
    unless column_exists?(:tenants, :enforce_broker_trusted_devices)
      add_column :tenants, :enforce_broker_trusted_devices, :boolean, null: false, default: false
    end

    execute <<~SQL
      UPDATE tenants SET enforce_broker_ip_allowlist = TRUE
       WHERE EXISTS (SELECT 1 FROM settings WHERE key = 'access_control_enforce_broker_ip_allowlist' AND value = 'true')
    SQL
    execute <<~SQL
      UPDATE tenants SET enforce_broker_trusted_devices = TRUE
       WHERE EXISTS (SELECT 1 FROM settings WHERE key = 'access_control_enforce_broker_trusted_devices' AND value = 'true')
    SQL
  end

  def down
    remove_column :tenants, :enforce_broker_trusted_devices if column_exists?(:tenants, :enforce_broker_trusted_devices)
    remove_column :tenants, :enforce_broker_ip_allowlist if column_exists?(:tenants, :enforce_broker_ip_allowlist)
  end
end
