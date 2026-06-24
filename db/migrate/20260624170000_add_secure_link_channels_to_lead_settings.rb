class AddSecureLinkChannelsToLeadSettings < ActiveRecord::Migration[7.1]
  def change
    # Por canal: qual notificação roteia o contato pelo link seguro /s/:token
    # (motor único: valida expiração, registra acesso e marca atendido no prazo).
    # Só vale quando o master `secure_links_enabled` está ligado. Default: todos.
    add_column :lead_settings, :secure_link_whatsapp, :boolean, default: true, null: false
    add_column :lead_settings, :secure_link_email,    :boolean, default: true, null: false
    add_column :lead_settings, :secure_link_push,     :boolean, default: true, null: false
  end
end
