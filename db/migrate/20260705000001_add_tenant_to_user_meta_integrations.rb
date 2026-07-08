class AddTenantToUserMetaIntegrations < ActiveRecord::Migration[7.1]
  # Modelo agência: o mesmo usuário poderá ter uma integração Meta POR CONTA
  # (Fase 3 multi-conta). A integração passa a saber seu tenant diretamente —
  # hoje o tenant só é inferível via admin_user, o que é frágil.
  # Presença é garantida no model (before_validation), não no banco, para o
  # deploy do código anteceder a migration sem quebrar.
  def up
    unless column_exists?(:user_meta_integrations, :tenant_id)
      add_reference :user_meta_integrations, :tenant, foreign_key: true, index: true
    end

    # Backfill: tenant da integração = tenant do admin que conectou.
    execute <<~SQL
      UPDATE user_meta_integrations
         SET tenant_id = admin_users.tenant_id
        FROM admin_users
       WHERE user_meta_integrations.tenant_id IS NULL
         AND user_meta_integrations.admin_user_id = admin_users.id
    SQL

    unless index_exists?(:user_meta_integrations, [:admin_user_id, :tenant_id], name: :idx_user_meta_integrations_on_user_and_tenant)
      add_index :user_meta_integrations, [:admin_user_id, :tenant_id],
                unique: true, name: :idx_user_meta_integrations_on_user_and_tenant
    end
  end

  def down
    if index_exists?(:user_meta_integrations, [:admin_user_id, :tenant_id], name: :idx_user_meta_integrations_on_user_and_tenant)
      remove_index :user_meta_integrations, name: :idx_user_meta_integrations_on_user_and_tenant
    end
    remove_reference :user_meta_integrations, :tenant, foreign_key: true if column_exists?(:user_meta_integrations, :tenant_id)
  end
end
