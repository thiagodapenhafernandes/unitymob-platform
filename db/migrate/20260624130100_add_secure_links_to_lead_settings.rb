class AddSecureLinksToLeadSettings < ActiveRecord::Migration[7.1]
  def change
    # Mascarar contato do lead na notificação WhatsApp com link seguro /s/:token.
    add_column :lead_settings, :secure_links_enabled, :boolean, default: false, null: false
    # Validade do link em dias (0 = nunca expira).
    add_column :lead_settings, :secure_link_expiry_days, :integer, default: 7, null: false
  end
end
