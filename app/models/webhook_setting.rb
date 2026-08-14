class WebhookSetting < ApplicationRecord
  include TenantScoped
  LEAD_CAPTURE_CACHE_KEY = "public_site:lead_capture_enabled".freeze
  FORM_DELIVERY_SCOPES = {
    "all" => "Todos os formulários",
    "categories" => "Categorias selecionadas",
    "forms" => "Formulários selecionados"
  }.freeze

  # Singleton pattern - apenas um registro de configuração
  validates :webhook_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  validates :whatsapp_webhook_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  validates :form_delivery_scope, inclusion: { in: FORM_DELIVERY_SCOPES.keys }
  
  scope :active, -> { where(enabled: true) }

  after_commit :clear_public_site_cache
  before_validation :normalize_form_filters

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

  def delivers_form?(origin_form, public_form: nil)
    return true if form_delivery_scope.blank? || form_delivery_scope == "all"

    case form_delivery_scope
    when "categories"
      return false unless public_form

      form_category_list.include?(public_form.category)
    when "forms"
      return false unless public_form

      public_form_id_list.include?(public_form.id)
    else
      true
    end
  end

  def form_category_list
    Array(form_categories).map(&:to_s).reject(&:blank?)
  end

  def public_form_id_list
    Array(public_form_ids).filter_map { |value| value.to_i if value.to_i.positive? }
  end

  def form_delivery_scope_label
    FORM_DELIVERY_SCOPES.fetch(form_delivery_scope, FORM_DELIVERY_SCOPES["all"])
  end
  
  def test_webhook
    return false unless active?
    
    target_url = whatsapp_webhook_url.presence || webhook_url
    
    WebhookService.send_form_data('test_webhook', {
      message: "Test webhook from #{tenant&.name.presence || 'Unitymob'}",
      timestamp: Time.current.iso8601
    }, url: target_url)
  end

  private

  def normalize_form_filters
    self.form_delivery_scope = form_delivery_scope.presence_in(FORM_DELIVERY_SCOPES.keys) || "all"
    self.form_categories = form_category_list
    self.public_form_ids = public_form_id_list
  end

  def clear_public_site_cache
    Rails.cache.delete("#{LEAD_CAPTURE_CACHE_KEY}:tenant:#{tenant_id}")
  end
end
