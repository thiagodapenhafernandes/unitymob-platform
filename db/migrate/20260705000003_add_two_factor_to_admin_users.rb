class AddTwoFactorToAdminUsers < ActiveRecord::Migration[7.1]
  # 2FA TOTP (Google Authenticator): otp_secret é cifrado no model via
  # `encrypts` (AR Encryption por ENV); backup codes guardam só digests BCrypt;
  # otp_consumed_timestep impede replay do mesmo código dentro da janela.
  def up
    add_column :admin_users, :otp_secret, :string unless column_exists?(:admin_users, :otp_secret)
    add_column :admin_users, :otp_enabled_at, :datetime unless column_exists?(:admin_users, :otp_enabled_at)
    add_column :admin_users, :otp_backup_codes, :jsonb, null: false, default: [] unless column_exists?(:admin_users, :otp_backup_codes)
    add_column :admin_users, :otp_consumed_timestep, :integer unless column_exists?(:admin_users, :otp_consumed_timestep)
  end

  def down
    remove_column :admin_users, :otp_consumed_timestep if column_exists?(:admin_users, :otp_consumed_timestep)
    remove_column :admin_users, :otp_backup_codes if column_exists?(:admin_users, :otp_backup_codes)
    remove_column :admin_users, :otp_enabled_at if column_exists?(:admin_users, :otp_enabled_at)
    remove_column :admin_users, :otp_secret if column_exists?(:admin_users, :otp_secret)
  end
end
