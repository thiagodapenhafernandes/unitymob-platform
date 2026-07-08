class AddTenantToEmailSettings < ActiveRecord::Migration[7.1]
  # email_settings era um singleton GLOBAL (SMTP da plataforma). Passa a aceitar
  # escopo por tenant com FALLBACK: a linha existente fica com tenant_id NULL =
  # global (comportamento atual preservado); cada conta pode "sombrear" salvando
  # a própria linha. UNIQUE parcial garante no máximo 1 email_settings por tenant
  # (a linha global NULL não entra no índice).
  def up
    unless column_exists?(:email_settings, :tenant_id)
      add_reference :email_settings, :tenant, foreign_key: true, index: true
    end

    unless index_exists?(:email_settings, :tenant_id, name: :idx_email_settings_on_tenant_unique)
      add_index :email_settings, :tenant_id, unique: true,
                where: "tenant_id IS NOT NULL", name: :idx_email_settings_on_tenant_unique
    end
  end

  def down
    if index_exists?(:email_settings, :tenant_id, name: :idx_email_settings_on_tenant_unique)
      remove_index :email_settings, name: :idx_email_settings_on_tenant_unique
    end
    remove_reference :email_settings, :tenant, foreign_key: true if column_exists?(:email_settings, :tenant_id)
  end
end
