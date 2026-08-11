class ContactSetting < ApplicationRecord
  include TenantScoped
  include PhoneNormalizable

  FOOTER_SOCIAL_LINK_FIELDS = [
    ["Facebook", :facebook_url],
    ["Instagram", :instagram_url],
    ["YouTube", :youtube_url],
    ["Blog", :blog_url],
    ["LinkedIn", :linkedin_url]
  ].freeze

  after_commit :clear_public_site_cache
  normalize_phone_fields :whatsapp_primary, :whatsapp_secondary, :phone

  # Singleton pattern
  def self.instance(tenant: Current.tenant || Tenant.public_for)
    raise ArgumentError, "Tenant obrigatório para configurações de contato" if tenant.blank?

    where(tenant: tenant).first_or_create!
  end

  def footer_social_links
    FOOTER_SOCIAL_LINK_FIELDS.filter_map do |platform, attribute|
      url = public_send(attribute).presence
      FooterSocialLink.new(platform:, url:) if url
    end
  end

  private

  def clear_public_site_cache
    WhatsappBusinessIntegration.clear_all_site_phone_settings_cache
  end
end
