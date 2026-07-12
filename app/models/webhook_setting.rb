class WebhookSetting < ApplicationRecord
  include TenantScoped
  LEAD_CAPTURE_CACHE_KEY = "public_site:lead_capture_enabled".freeze

  # Singleton pattern - apenas um registro de configuração
  validates :webhook_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  validates :whatsapp_webhook_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  
  scope :active, -> { where(enabled: true) }

  after_commit :clear_public_site_cache

  def self.lead_capture_enabled?(tenant: Current.tenant)
    return false unless tenant

    Rails.cache.fetch("#{LEAD_CAPTURE_CACHE_KEY}:tenant:#{tenant.id}", expires_in: 5.minutes) do
      where(tenant: tenant).active.where(lead_capture_enabled: true).exists?
    end
  end
  
  def active?
    enabled && (webhook_url.present? || whatsapp_webhook_url.present?)
  end

  def whatsapp_webhook_active?
    enabled && whatsapp_webhook_url.present?
  end
  
  def test_webhook
    return false unless active?
    
    target_url = whatsapp_webhook_url.presence || webhook_url
    
    WebhookService.send_form_data('test_webhook', {
      message: 'Test webhook from Salute Imóveis',
      timestamp: Time.current.iso8601
    }, url: target_url)
  end

  private

  def clear_public_site_cache
    Rails.cache.delete("#{LEAD_CAPTURE_CACHE_KEY}:tenant:#{tenant_id}")
  end
end
