class WebhookSetting < ApplicationRecord
  # Singleton pattern - apenas um registro de configuração
  validates :webhook_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  validates :whatsapp_webhook_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  
  scope :active, -> { where(enabled: true) }
  
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
end
