class LoversIntegrationSetting
  include ActiveModel::Model
  include ActiveModel::Attributes

  PREFIX = "lovers.leads".freeze

  ENABLED_KEY = "#{PREFIX}.enabled".freeze
  API_TOKEN_KEY = "#{PREFIX}.api_token".freeze
  DEFAULT_ORIGIN_KEY = "#{PREFIX}.default_origin".freeze
  SYNC_START_DATE_KEY = "#{PREFIX}.sync_start_date".freeze
  LAST_SYNC_AT_KEY = "#{PREFIX}.last_sync_at".freeze
  LAST_SYNC_STATUS_KEY = "#{PREFIX}.last_sync_status".freeze
  LAST_SYNC_MESSAGE_KEY = "#{PREFIX}.last_sync_message".freeze

  DEFAULT_ORIGIN = "Lovers".freeze

  HUMAN_ATTRIBUTES = {
    "enabled" => "Recepção ativa",
    "api_token" => "Token da API",
    "default_origin" => "Origem padrão",
    "sync_start_date" => "Sincronizar desde"
  }.freeze

  attribute :tenant
  attribute :enabled, :boolean, default: false
  attribute :api_token, :string
  attribute :default_origin, :string, default: DEFAULT_ORIGIN
  attribute :sync_start_date, :date

  validates :tenant, presence: true
  validates :default_origin, presence: true
  validate :validate_required_fields_when_enabled

  def self.current(tenant: Current.tenant)
    raise ArgumentError, "Tenant obrigatório para configurar Lovers" if tenant.blank?

    new(
      tenant:,
      enabled: Setting.tenant_get(ENABLED_KEY, "false", tenant:) == "true",
      default_origin: Setting.tenant_get(DEFAULT_ORIGIN_KEY, DEFAULT_ORIGIN, tenant:),
      sync_start_date: parse_date(Setting.tenant_get(SYNC_START_DATE_KEY, nil, tenant:))
    )
  end

  def self.human_attribute_name(attribute, options = {})
    HUMAN_ATTRIBUTES[attribute.to_s] || super
  end

  def save
    return false unless valid?

    Setting.set(ENABLED_KEY, enabled? ? "true" : "false", "Ativa entrada de leads via Lovers", tenant:)
    Setting.set(API_TOKEN_KEY, normalized_api_token, "Token da API Lovers", tenant:) if normalized_api_token.present?
    Setting.set(DEFAULT_ORIGIN_KEY, normalized_default_origin, "Origem padrão para leads Lovers", tenant:)
    Setting.set(SYNC_START_DATE_KEY, normalized_sync_start_date, "Data inicial para sincronização Lovers", tenant:)

    true
  end

  def enabled?
    ActiveModel::Type::Boolean.new.cast(enabled)
  end

  def connected?
    api_token_configured?
  end

  def configured?
    enabled? && connected?
  end

  def api_token_configured?
    stored_api_token.present?
  end

  def stored_api_token
    Setting.tenant_get(API_TOKEN_KEY, nil, tenant:).to_s.presence
  end

  def last_sync_at
    value = Setting.tenant_get(LAST_SYNC_AT_KEY, nil, tenant:).to_s.presence
    Time.zone.parse(value) if value.present?
  rescue ArgumentError
    nil
  end

  def last_sync_status
    Setting.tenant_get(LAST_SYNC_STATUS_KEY, nil, tenant:).to_s.presence
  end

  def last_sync_message
    Setting.tenant_get(LAST_SYNC_MESSAGE_KEY, nil, tenant:).to_s.presence
  end

  def sync_start_on
    sync_start_date || last_sync_at&.to_date || 7.days.ago.to_date
  end

  def self.save_sync_status!(tenant:, status:, message:, synced_at: Time.current)
    Setting.set(LAST_SYNC_STATUS_KEY, status.to_s, "Status da sincronização Lovers", tenant:)
    Setting.set(LAST_SYNC_MESSAGE_KEY, message.to_s.truncate(500), "Mensagem da sincronização Lovers", tenant:)
    Setting.set(LAST_SYNC_AT_KEY, synced_at.iso8601, "Última sincronização Lovers", tenant:)
  end

  def self.clear_connection!(tenant:)
    [API_TOKEN_KEY, LAST_SYNC_STATUS_KEY, LAST_SYNC_MESSAGE_KEY, LAST_SYNC_AT_KEY].each do |key|
      Setting.set(key, "", nil, tenant:)
    end
  end

  def self.parse_date(value)
    Date.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  private

  def validate_required_fields_when_enabled
    return unless enabled?
    return if normalized_api_token.present? || api_token_configured?

    errors.add(:api_token, "não pode ficar em branco")
  end

  def normalized_api_token
    api_token.to_s.strip
  end

  def normalized_default_origin
    default_origin.to_s.strip.presence || DEFAULT_ORIGIN
  end

  def normalized_sync_start_date
    sync_start_date&.iso8601
  end
end
