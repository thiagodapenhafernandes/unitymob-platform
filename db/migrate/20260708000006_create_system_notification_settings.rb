class CreateSystemNotificationSettings < ActiveRecord::Migration[7.1]
  # Singleton GLOBAL da plataforma (sem tenant_id): credenciais do WhatsApp/Meta
  # usadas para NOTIFICAR o operador do sistema e para o fallback global das
  # contas que aderem (use_global_whatsapp_fallback). As colunas *_token/*_secret
  # guardam ciphertext — a criptografia é feita no MODEL via `encrypts`, por isso
  # aqui são apenas text/string (o schema não sabe que estão encriptadas).
  def up
    return if table_exists?(:system_notification_settings)

    create_table :system_notification_settings do |t|
      t.boolean :whatsapp_enabled, default: false, null: false
      t.text    :whatsapp_access_token
      t.string  :whatsapp_phone_number_id
      t.string  :whatsapp_business_account_id
      t.string  :whatsapp_template_name
      t.text    :facebook_app_secret
      t.text    :whatsapp_app_secret

      t.timestamps
    end
  end

  def down
    drop_table :system_notification_settings if table_exists?(:system_notification_settings)
  end
end
