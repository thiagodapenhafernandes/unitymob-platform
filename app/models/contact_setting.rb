class ContactSetting < ApplicationRecord
  after_commit :clear_public_site_cache

  # Singleton pattern
  def self.instance
    first_or_create!(
      whatsapp_primary: '5547991234567',
      phone: '(47) 3311-1067',
      email_primary: 'contato@saluteimoveis.com',
      address: 'Balneário Camboriú - SC'
    )
  end

  private

  def clear_public_site_cache
    WhatsappBusinessIntegration.clear_all_site_phone_settings_cache
  end
end
