class WebhookSetting < ApplicationRecord
  include PublicSite::BumpsPageVersion
  include TenantScoped
  include EncryptionAvailability
  encrypts :webhook_secret
  has_many :google_stage_conversion_events, dependent: :nullify
  validates :tenant_id, uniqueness: { conditions: -> { where(google_conversions_enabled: true) } }, if: :google_conversions_enabled?
  validate :valid_google_destination
  before_validation :normalize_google_qualification_source

  def google_destination_url
    whatsapp_webhook_url.presence || webhook_url
  end

  def normalize_google_qualification_source
    return unless google_conversions_enabled? && tenant&.lead_pipeline_stages&.where(active: true, google_event: "qualify_lead")&.exists?

    self.subscribed_events = Array(subscribed_events) - ["qualified_lead"]
  end

  def valid_google_destination
    return unless google_conversions_enabled?

    errors.add(:base, "Configure as chaves de criptografia para ativar conversões Google.") unless encryption_ready?
    errors.add(:webhook_url, "deve usar HTTPS para conversões Google") unless google_destination_url.to_s.start_with?("https://")
  end

  LEAD_CAPTURE_CACHE_KEY = "public_site:lead_capture_enabled".freeze
  FORM_DELIVERY_SCOPES = {
    "all" => "Todos os formulários",
    "categories" => "Categorias selecionadas",
    "forms" => "Formulários selecionados"
  }.freeze
  EVENTS = {
    "lead_created" => "Lead capturado no site",
    "lead_inquiry" => "Nova consulta de lead existente",
    "form_submitted" => "Formulário enviado",
    "lead_stage_changed" => "Etapa do lead alterada",
    "lead_qualification_changed" => "Qualificação alterada",
    "qualified_lead" => "Lead marcado como qualificado"
  }.freeze
  DEFAULT_EVENTS = %w[lead_created lead_inquiry form_submitted].freeze

  # Singleton pattern - apenas um registro de configuração
  validates :webhook_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  validates :whatsapp_webhook_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  validates :form_delivery_scope, inclusion: { in: FORM_DELIVERY_SCOPES.keys }
  validate :valid_subscribed_events
  validate :public_forms_belong_to_tenant
  
  scope :active, -> { where(enabled: true) }

  after_commit :clear_public_site_cache
  before_validation :normalize_form_filters

  def delivers_event?(event_name)
    Array(subscribed_events).include?(event_name.to_s)
  end

  def self.event_name_for(origin_form, data = {})
    return origin_form.to_s if EVENTS.key?(origin_form.to_s) || origin_form.to_s == "test_webhook"
    return "form_submitted" unless origin_form.to_s == "whatsapp_lead"

    data.to_h.with_indifferent_access[:complemented_inquiry] ? "lead_inquiry" : "lead_created"
  end

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
    
    WebhookService.send_form_data('test_webhook', test_data, url: target_url, tenant: tenant)
  end

  def test_payload
    WebhookService.test_payload(test_data, tenant: tenant)
  end

  def test_data
    {
      message: "Test webhook from #{tenant&.name.presence || 'Unitymob'}",
      timestamp: Time.current.iso8601,
      utm_source: "unitymob_test",
      utm_medium: "webhook_test",
      utm_campaign: "teste_integracao",
      diagnostic: true,
      id: "unitymob-test-#{SecureRandom.uuid}", name: "Teste Unitymob",
      email: "diagnostic@example.test", phone: "+5547999999999",
      business_type: "sale", value: 150, currency: "BRL",
      property_code: "TESTE-SEM-IMOVEL", placement: "diagnostic",
      client_ip_address: "192.0.2.1", client_user_agent: "Unitymob diagnostic (synthetic)",
      gclid: "TEST_GCLID", gbraid: "TEST_GBRAID", wbraid: "TEST_WBRAID",
      fbc: "fb.1.1760100000000.TEST", fbp: "fb.1.1760100000000.1234567890",
      client_id: "1234567890.1760100000"
    }
  end

  private

  def normalize_form_filters
    self.form_delivery_scope = form_delivery_scope.presence_in(FORM_DELIVERY_SCOPES.keys) || "all"
    self.form_categories = form_category_list
    self.public_form_ids = public_form_id_list
    self.subscribed_events = Array(subscribed_events).map(&:to_s).reject(&:blank?).uniq
  end

  def valid_subscribed_events
    errors.add(:subscribed_events, "selecione pelo menos um evento válido") if
      (Array(subscribed_events).empty? && !google_conversions_enabled?) || (Array(subscribed_events) - EVENTS.keys).any?
  end

  def public_forms_belong_to_tenant
    ids = public_form_id_list
    return if ids.empty?
    errors.add(:public_form_ids, "devem pertencer à conta") unless tenant&.public_forms&.where(id: ids)&.count == ids.size
  end

  def clear_public_site_cache
    Rails.cache.delete("#{LEAD_CAPTURE_CACHE_KEY}:tenant:#{tenant_id}")
  end
end
