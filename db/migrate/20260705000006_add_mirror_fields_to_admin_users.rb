class AddMirrorFieldsToAdminUsers < ActiveRecord::Migration[7.1]
  # Usuário ESPELHO: linha comum de admin_users no tenant convidado, linkada ao
  # usuário primário. E-mail global continua único: o espelho usa e-mail
  # sintético; o e-mail real de contato/notificação vai em contact_email.
  def up
    unless column_exists?(:admin_users, :primary_admin_user_id)
      add_column :admin_users, :primary_admin_user_id, :bigint
      add_foreign_key :admin_users, :admin_users, column: :primary_admin_user_id
      add_index :admin_users, :primary_admin_user_id
    end

    add_column :admin_users, :contact_email, :string unless column_exists?(:admin_users, :contact_email)

    # Um espelho por pessoa por conta.
    execute <<~SQL
      CREATE UNIQUE INDEX IF NOT EXISTS idx_admin_users_one_mirror_per_tenant
      ON admin_users (primary_admin_user_id, tenant_id)
      WHERE primary_admin_user_id IS NOT NULL
    SQL

    # Espelho nunca é Admin do Sistema.
    execute <<~SQL
      DO $$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_admin_users_mirror_not_super_admin') THEN
          ALTER TABLE admin_users
            ADD CONSTRAINT chk_admin_users_mirror_not_super_admin
            CHECK (primary_admin_user_id IS NULL OR super_admin = false);
        END IF;
      END $$
    SQL
  end

  def down
    execute "ALTER TABLE admin_users DROP CONSTRAINT IF EXISTS chk_admin_users_mirror_not_super_admin"
    execute "DROP INDEX IF EXISTS idx_admin_users_one_mirror_per_tenant"
    remove_column :admin_users, :contact_email if column_exists?(:admin_users, :contact_email)
    if column_exists?(:admin_users, :primary_admin_user_id)
      remove_foreign_key :admin_users, column: :primary_admin_user_id
      remove_column :admin_users, :primary_admin_user_id
    end
  end
end
