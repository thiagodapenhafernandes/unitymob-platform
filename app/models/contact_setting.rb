class ContactSetting < ApplicationRecord
  include TenantScoped
  include PhoneNormalizable

  after_commit :clear_public_site_cache
  normalize_phone_fields :whatsapp_primary, :whatsapp_secondary, :phone

  # Singleton pattern
  def self.instance(tenant: Current.tenant || Tenant.public_for)
    raise ArgumentError, "Tenant obrigatório para configurações de contato" if tenant.blank?

    where(tenant: tenant).first_or_create!
  end

  private

  def clear_public_site_cache
    WhatsappBusinessIntegration.clear_all_site_phone_settings_cache
  end
end
