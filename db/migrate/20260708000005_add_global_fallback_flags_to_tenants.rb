class AddGlobalFallbackFlagsToTenants < ActiveRecord::Migration[7.1]
  # Quando um tenant NÃO configura seu próprio WhatsApp/Email, estes flags
  # autorizam explicitamente o uso da configuração GLOBAL da plataforma como
  # fallback. Default false: sem opt-in, a conta sem config simplesmente não
  # dispara pelo canal (nada de vazar credencial global sem consentimento).
  def up
    unless column_exists?(:tenants, :use_global_whatsapp_fallback)
      add_column :tenants, :use_global_whatsapp_fallback, :boolean, default: false, null: false
    end
    unless column_exists?(:tenants, :use_global_email_fallback)
      add_column :tenants, :use_global_email_fallback, :boolean, default: false, null: false
    end
  end

  def down
    remove_column :tenants, :use_global_email_fallback    if column_exists?(:tenants, :use_global_email_fallback)
    remove_column :tenants, :use_global_whatsapp_fallback if column_exists?(:tenants, :use_global_whatsapp_fallback)
  end
end
