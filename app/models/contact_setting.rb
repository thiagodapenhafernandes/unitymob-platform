class ContactSetting < ApplicationRecord
  # Singleton pattern
  def self.instance
    first_or_create!(
      whatsapp_primary: '5547991234567',
      phone: '(47) 3311-1067',
      email_primary: 'contato@saluteimoveis.com',
      address: 'Balneário Camboriú - SC'
    )
  end
end
