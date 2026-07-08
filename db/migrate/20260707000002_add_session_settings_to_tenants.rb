class AddSessionSettingsToTenants < ActiveRecord::Migration[7.1]
  # Expiração de sessão configurável por conta (tela Segurança de Acesso):
  # - session_timeout_enabled/_days: timeout de inatividade do Devise por tenant;
  # - session_remember_days: cap da validade do "lembrar deste dispositivo"
  #   (null = padrão do Devise);
  # - session_epoch_at: "Encerrar todas as sessões" — sessões carimbadas antes
  #   desse instante são derrubadas no próximo request.
  def up
    add_column :tenants, :session_timeout_enabled, :boolean, null: false, default: false unless column_exists?(:tenants, :session_timeout_enabled)
    add_column :tenants, :session_timeout_days, :integer, default: 7 unless column_exists?(:tenants, :session_timeout_days)
    add_column :tenants, :session_remember_days, :integer unless column_exists?(:tenants, :session_remember_days)
    add_column :tenants, :session_epoch_at, :datetime unless column_exists?(:tenants, :session_epoch_at)
  end

  def down
    remove_column :tenants, :session_epoch_at if column_exists?(:tenants, :session_epoch_at)
    remove_column :tenants, :session_remember_days if column_exists?(:tenants, :session_remember_days)
    remove_column :tenants, :session_timeout_days if column_exists?(:tenants, :session_timeout_days)
    remove_column :tenants, :session_timeout_enabled if column_exists?(:tenants, :session_timeout_enabled)
  end
end
