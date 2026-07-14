class GoogleSheetsIntegrationSetting
  require "uri"

  include ActiveModel::Model
  include ActiveModel::Attributes

  PREFIX = "google_sheets.captacoes".freeze

  ENABLED_KEY = "#{PREFIX}.enabled".freeze
  WEB_APP_URL_KEY = "#{PREFIX}.web_app_url".freeze
  TOKEN_KEY = "#{PREFIX}.token".freeze
  WORKSHEET_NAME_KEY = "#{PREFIX}.worksheet_name".freeze
  KEY_COLUMN_KEY = "#{PREFIX}.key_column".freeze

  DEFAULT_WORKSHEET_NAME = "Captações".freeze
  DEFAULT_KEY_COLUMN = "Cód. imóvel CRM".freeze
  HUMAN_ATTRIBUTES = {
    "enabled" => "Sincronização ativa",
    "web_app_url" => "URL do Web App",
    "token" => "Token de segurança",
    "worksheet_name" => "Nome da aba",
    "key_column" => "Coluna-chave"
  }.freeze

  attribute :enabled, :boolean, default: false
  attribute :tenant
  attribute :web_app_url, :string
  attribute :token, :string
  attribute :worksheet_name, :string, default: DEFAULT_WORKSHEET_NAME
  attribute :key_column, :string, default: DEFAULT_KEY_COLUMN

  validates :worksheet_name, presence: true
  validates :key_column, presence: true
  validates :tenant, presence: true
  validate :validate_required_fields_when_enabled
  validate :validate_web_app_url

  def self.current(tenant: Current.tenant)
    raise ArgumentError, "Tenant obrigatório para configurar Google Sheets" if tenant.blank?

    new(
      tenant: tenant,
      enabled: Setting.get(ENABLED_KEY, "false", tenant: tenant) == "true",
      web_app_url: Setting.get(WEB_APP_URL_KEY, "", tenant: tenant),
      worksheet_name: Setting.get(WORKSHEET_NAME_KEY, DEFAULT_WORKSHEET_NAME, tenant: tenant),
      key_column: Setting.get(KEY_COLUMN_KEY, DEFAULT_KEY_COLUMN, tenant: tenant)
    )
  end

  def self.connected?(tenant: Current.tenant)
    raise ArgumentError, "Tenant obrigatório para consultar Google Sheets" if tenant.blank?

    Setting.get(WEB_APP_URL_KEY, tenant: tenant).present? && Setting.get(TOKEN_KEY, tenant: tenant).present?
  end

  def self.human_attribute_name(attribute, options = {})
    HUMAN_ATTRIBUTES[attribute.to_s] || super
  end

  def connected?
    self.class.connected?(tenant: tenant)
  end

  def save
    return false unless valid?

    Setting.set(ENABLED_KEY, enabled? ? "true" : "false", "Ativa envio de captações para Google Sheets", tenant: tenant)
    Setting.set(WEB_APP_URL_KEY, normalized_web_app_url, "URL do Web App do Google Apps Script para captações", tenant: tenant)
    Setting.set(WORKSHEET_NAME_KEY, normalized_worksheet_name, "Nome da aba da planilha de captações", tenant: tenant)
    Setting.set(KEY_COLUMN_KEY, normalized_key_column, "Coluna-chave usada para atualizar captações no Google Sheets", tenant: tenant)
    Setting.set(TOKEN_KEY, token.to_s.strip, "Token de segurança do Web App de captações", tenant: tenant) if token.to_s.strip.present?

    true
  end

  def enabled?
    ActiveModel::Type::Boolean.new.cast(enabled)
  end

  def token_configured?
    Setting.get(TOKEN_KEY, tenant: tenant).present?
  end

  private

  def validate_required_fields_when_enabled
    return unless enabled?

    errors.add(:web_app_url, "não pode ficar em branco") if normalized_web_app_url.blank?
    errors.add(:token, "não pode ficar em branco") unless token.to_s.strip.present? || token_configured?
  end

  def validate_web_app_url
    return if normalized_web_app_url.blank?

    uri = URI.parse(normalized_web_app_url)
    errors.add(:web_app_url, "precisa ser uma URL HTTP ou HTTPS") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:web_app_url, "precisa ser uma URL válida")
  end

  def normalized_web_app_url
    web_app_url.to_s.strip
  end

  def normalized_worksheet_name
    worksheet_name.to_s.strip.presence || DEFAULT_WORKSHEET_NAME
  end

  def normalized_key_column
    key_column.to_s.strip.presence || DEFAULT_KEY_COLUMN
  end
end
