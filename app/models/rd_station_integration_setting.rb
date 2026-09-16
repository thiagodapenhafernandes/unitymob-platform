class RdStationIntegrationSetting
  include ActiveModel::Model
  include ActiveModel::Attributes

  PREFIX = "rd_station.leads".freeze

  ENABLED_KEY = "#{PREFIX}.enabled".freeze
  API_TOKEN_KEY = "#{PREFIX}.api_token".freeze
  REFRESH_TOKEN_KEY = "#{PREFIX}.refresh_token".freeze
  TOKEN_EXPIRES_AT_KEY = "#{PREFIX}.token_expires_at".freeze
  CLIENT_ID_KEY = "#{PREFIX}.client_id".freeze
  CLIENT_SECRET_KEY = "#{PREFIX}.client_secret".freeze
  WEBHOOK_SECRET_KEY = "#{PREFIX}.webhook_secret".freeze
  WEBHOOK_STATUS_KEY = "#{PREFIX}.webhook_status".freeze
  WEBHOOK_MESSAGE_KEY = "#{PREFIX}.webhook_message".freeze
  DEFAULT_BUSINESS_TYPE_KEY = "#{PREFIX}.default_business_type".freeze
  DEFAULT_ORIGIN_KEY = "#{PREFIX}.default_origin".freeze

  DEFAULT_ORIGIN = "RD Station".freeze
  BUSINESS_TYPES = {
    "auto" => "Detectar automaticamente",
    "venda" => "Venda",
    "locacao" => "Locação",
    "ambos" => "Venda e locação"
  }.freeze

  HUMAN_ATTRIBUTES = {
    "enabled" => "Recepção ativa",
    "client_id" => "Client ID",
    "client_secret" => "Client secret",
    "api_token" => "Access token",
    "webhook_secret" => "Segredo do webhook",
    "default_business_type" => "Tipo comercial padrão",
    "default_origin" => "Origem padrão"
  }.freeze

  attribute :tenant
  attribute :enabled, :boolean, default: false
  attribute :client_id, :string
  attribute :client_secret, :string
  attribute :api_token, :string
  attribute :webhook_secret, :string
  attribute :default_business_type, :string, default: "auto"
  attribute :default_origin, :string, default: DEFAULT_ORIGIN

  validates :tenant, presence: true
  validates :default_origin, presence: true
  validates :default_business_type, inclusion: { in: BUSINESS_TYPES.keys }
  validate :validate_required_fields_when_enabled
  validate :validate_webhook_secret_uniqueness

  def self.current(tenant: Current.tenant)
    raise ArgumentError, "Tenant obrigatório para configurar RD Station" if tenant.blank?

    new(
      tenant: tenant,
      enabled: Setting.tenant_get(ENABLED_KEY, "false", tenant: tenant) == "true",
      client_id: Setting.tenant_get(CLIENT_ID_KEY, "", tenant: tenant),
      default_business_type: Setting.tenant_get(DEFAULT_BUSINESS_TYPE_KEY, "auto", tenant: tenant),
      default_origin: Setting.tenant_get(DEFAULT_ORIGIN_KEY, DEFAULT_ORIGIN, tenant: tenant)
    )
  end

  def ensure_webhook_secret!
    return stored_webhook_secret if webhook_secret_configured?

    secret = self.class.generate_unique_webhook_secret
    Setting.set(WEBHOOK_SECRET_KEY, secret, "Segredo do webhook RD Station", tenant: tenant)
    secret
  end

  def self.human_attribute_name(attribute, options = {})
    HUMAN_ATTRIBUTES[attribute.to_s] || super
  end

  def save
    self.webhook_secret = SecureRandom.urlsafe_base64(32) if normalized_webhook_secret.blank? && !webhook_secret_configured?

    return false unless valid?

    Setting.set(ENABLED_KEY, enabled? ? "true" : "false", "Ativa entrada de leads via RD Station", tenant: tenant)
    Setting.set(CLIENT_ID_KEY, normalized_client_id, "Client ID RD Station", tenant: tenant)
    Setting.set(CLIENT_SECRET_KEY, normalized_client_secret, "Client secret RD Station", tenant: tenant) if normalized_client_secret.present?
    Setting.set(API_TOKEN_KEY, normalized_api_token, "Token da API RD Station", tenant: tenant) if normalized_api_token.present?
    Setting.set(WEBHOOK_SECRET_KEY, normalized_webhook_secret, "Segredo do webhook RD Station", tenant: tenant) if normalized_webhook_secret.present?
    Setting.set(DEFAULT_BUSINESS_TYPE_KEY, normalized_default_business_type, "Tipo comercial padrão para leads RD Station", tenant: tenant)
    Setting.set(DEFAULT_ORIGIN_KEY, normalized_default_origin, "Origem padrão para leads RD Station", tenant: tenant)

    true
  end

  def enabled?
    ActiveModel::Type::Boolean.new.cast(enabled)
  end

  def configured?
    client_configured? && access_token.present? && webhook_secret_configured?
  end

  def connected?
    access_token.present?
  end

  def client_configured?
    normalized_client_id.present? && client_secret_configured?
  end

  def access_token_configured?
    Setting.tenant_get(API_TOKEN_KEY, nil, tenant: tenant).present?
  end
  alias_method :api_token_configured?, :access_token_configured?

  def access_token
    Setting.tenant_get(API_TOKEN_KEY, nil, tenant: tenant).to_s.presence
  end

  def refresh_token
    Setting.tenant_get(REFRESH_TOKEN_KEY, nil, tenant: tenant).to_s.presence
  end

  def token_expires_at
    value = Setting.tenant_get(TOKEN_EXPIRES_AT_KEY, nil, tenant: tenant).to_s.presence
    Time.zone.parse(value) if value.present?
  rescue ArgumentError
    nil
  end

  def access_token_expired?(buffer: 5.minutes)
    expires_at = token_expires_at
    expires_at.present? && expires_at <= Time.current + buffer
  end

  def stored_client_secret
    Setting.tenant_get(CLIENT_SECRET_KEY, nil, tenant: tenant).to_s.presence
  end

  def client_secret_configured?
    stored_client_secret.present?
  end

  def webhook_secret_configured?
    Setting.tenant_get(WEBHOOK_SECRET_KEY, nil, tenant: tenant).present?
  end

  def stored_webhook_secret
    Setting.tenant_get(WEBHOOK_SECRET_KEY, nil, tenant: tenant).to_s.presence
  end

  def webhook_status
    Setting.tenant_get(WEBHOOK_STATUS_KEY, nil, tenant: tenant).to_s.presence
  end

  def webhook_message
    Setting.tenant_get(WEBHOOK_MESSAGE_KEY, nil, tenant: tenant).to_s.presence
  end

  def webhook_url
    Rails.application.routes.url_helpers.webhooks_rd_station_url(token: stored_webhook_secret)
  end

  def self.find_tenant_by_webhook_secret(secret)
    Setting.find_by(key: WEBHOOK_SECRET_KEY, value: secret.to_s)&.tenant
  end

  def self.generate_unique_webhook_secret
    loop do
      secret = SecureRandom.urlsafe_base64(32)
      return secret unless Setting.exists?(key: WEBHOOK_SECRET_KEY, value: secret)
    end
  end

  def self.save_oauth_tokens!(tenant:, payload:)
    Setting.set(API_TOKEN_KEY, payload.fetch("access_token").to_s, "Access token RD Station", tenant: tenant)
    Setting.set(REFRESH_TOKEN_KEY, payload["refresh_token"].to_s, "Refresh token RD Station", tenant: tenant) if payload["refresh_token"].present?
    expires_in = payload["expires_in"].to_i
    Setting.set(TOKEN_EXPIRES_AT_KEY, (Time.current + expires_in.seconds).iso8601, "Expiração do token RD Station", tenant: tenant) if expires_in.positive?
  end

  def self.save_webhook_status!(tenant:, status:, message:)
    Setting.set(WEBHOOK_STATUS_KEY, status.to_s, "Status dos webhooks RD Station", tenant: tenant)
    Setting.set(WEBHOOK_MESSAGE_KEY, message.to_s.truncate(500), "Mensagem dos webhooks RD Station", tenant: tenant)
  end

  private

  def validate_required_fields_when_enabled
    return unless enabled?

    errors.add(:client_id, "não pode ficar em branco") if normalized_client_id.blank?
    errors.add(:client_secret, "não pode ficar em branco") unless normalized_client_secret.present? || client_secret_configured?
  end

  def validate_webhook_secret_uniqueness
    secret = normalized_webhook_secret
    return if secret.blank?

    owner = Setting.find_by(key: WEBHOOK_SECRET_KEY, value: secret)&.tenant
    return if owner.blank? || owner == tenant

    errors.add(:webhook_secret, "já está em uso por outra conta")
  end

  def normalized_client_id
    client_id.to_s.strip
  end

  def normalized_client_secret
    client_secret.to_s.strip
  end

  def normalized_api_token
    api_token.to_s.strip
  end

  def normalized_webhook_secret
    webhook_secret.to_s.strip
  end

  def normalized_default_business_type
    default_business_type.to_s.presence_in(BUSINESS_TYPES.keys) || "auto"
  end

  def normalized_default_origin
    default_origin.to_s.strip.presence || DEFAULT_ORIGIN
  end
end
