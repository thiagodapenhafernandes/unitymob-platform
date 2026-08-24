require "uri"

class TrackingIntegrationSetting
  include ActiveModel::Model
  include ActiveModel::Attributes

  PREFIX = "tracking".freeze

  GTM_ENABLED_KEY = "#{PREFIX}.google_tag_manager.enabled".freeze
  GTM_CONTAINER_ID_KEY = "#{PREFIX}.google_tag_manager.container_id".freeze
  META_PIXEL_ENABLED_KEY = "#{PREFIX}.meta_pixel.enabled".freeze
  META_PIXEL_ID_KEY = "#{PREFIX}.meta_pixel.pixel_id".freeze
  GOOGLE_ADS_ENABLED_KEY = "#{PREFIX}.google_ads.enabled".freeze
  GOOGLE_ADS_CONVERSION_ID_KEY = "#{PREFIX}.google_ads.conversion_id".freeze
  GOOGLE_SITE_VERIFICATION_TOKEN_KEY = "#{PREFIX}.google_site_verification.token".freeze
  RD_STATION_ENABLED_KEY = "#{PREFIX}.rd_station.enabled".freeze
  RD_STATION_LOADER_URL_KEY = "#{PREFIX}.rd_station.loader_url".freeze
  CACHE_KEY = "public_site:tracking_integration_setting".freeze

  HUMAN_ATTRIBUTES = {
    "google_tag_manager_enabled" => "Google Tag Manager ativo",
    "google_tag_manager_container_id" => "ID do container GTM",
    "meta_pixel_enabled" => "Pixel da Meta ativo",
    "meta_pixel_id" => "ID do Pixel da Meta",
    "google_ads_enabled" => "Google Ads ativo",
    "google_ads_conversion_id" => "ID de conversão do Google Ads",
    "google_site_verification_token" => "Token de verificação do Google",
    "rd_station_enabled" => "RD Station ativo",
    "rd_station_loader_url" => "URL do loader RD Station"
  }.freeze

  attribute :google_tag_manager_enabled, :boolean, default: false
  attribute :google_tag_manager_container_id, :string
  attribute :meta_pixel_enabled, :boolean, default: false
  attribute :meta_pixel_id, :string
  attribute :google_ads_enabled, :boolean, default: false
  attribute :google_ads_conversion_id, :string
  attribute :google_site_verification_token, :string
  attribute :rd_station_enabled, :boolean, default: false
  attribute :rd_station_loader_url, :string

  validate :validate_google_tag_manager
  validate :validate_meta_pixel
  validate :validate_google_ads
  validate :validate_google_site_verification
  validate :validate_rd_station

  attr_reader :tenant

  def initialize(attributes = {}, tenant: Current.tenant)
    @tenant = tenant
    super(attributes)
  end

  def self.current(tenant: Current.tenant)
    raise ArgumentError, "Tenant obrigatório para rastreamento" unless tenant

    Rails.cache.fetch(cache_key(tenant), expires_in: 5.minutes) do
      build_current(tenant: tenant)
    end
  end

  def self.build_current(tenant: Current.tenant)
    new({
      google_tag_manager_enabled: Setting.tenant_get(GTM_ENABLED_KEY, "false", tenant: tenant) == "true",
      google_tag_manager_container_id: Setting.tenant_get(GTM_CONTAINER_ID_KEY, "", tenant: tenant),
      meta_pixel_enabled: Setting.tenant_get(META_PIXEL_ENABLED_KEY, "false", tenant: tenant) == "true",
      meta_pixel_id: Setting.tenant_get(META_PIXEL_ID_KEY, "", tenant: tenant),
      google_ads_enabled: Setting.tenant_get(GOOGLE_ADS_ENABLED_KEY, "false", tenant: tenant) == "true",
      google_ads_conversion_id: Setting.tenant_get(GOOGLE_ADS_CONVERSION_ID_KEY, "", tenant: tenant),
      google_site_verification_token: Setting.tenant_get(GOOGLE_SITE_VERIFICATION_TOKEN_KEY, "", tenant: tenant),
      rd_station_enabled: Setting.tenant_get(RD_STATION_ENABLED_KEY, "false", tenant: tenant) == "true",
      rd_station_loader_url: Setting.tenant_get(RD_STATION_LOADER_URL_KEY, "", tenant: tenant)
    }, tenant: tenant)
  end

  def self.human_attribute_name(attribute, options = {})
    HUMAN_ATTRIBUTES[attribute.to_s] || super
  end

  def self.google_tag_manager_enabled?(tenant: Current.tenant)
    Setting.tenant_get(GTM_ENABLED_KEY, "false", tenant: tenant) == "true" && google_tag_manager_container_id(tenant: tenant).present?
  end

  def self.google_tag_manager_container_id(tenant: Current.tenant)
    normalize_gtm_container_id(Setting.tenant_get(GTM_CONTAINER_ID_KEY, "", tenant: tenant))
  end

  def self.meta_pixel_enabled?(tenant: Current.tenant)
    Setting.tenant_get(META_PIXEL_ENABLED_KEY, "false", tenant: tenant) == "true" && meta_pixel_id(tenant: tenant).present?
  end

  def self.meta_pixel_id(tenant: Current.tenant)
    normalize_meta_pixel_id(Setting.tenant_get(META_PIXEL_ID_KEY, "", tenant: tenant))
  end

  def self.google_ads_enabled?(tenant: Current.tenant)
    Setting.tenant_get(GOOGLE_ADS_ENABLED_KEY, "false", tenant: tenant) == "true" && google_ads_conversion_id(tenant: tenant).present?
  end

  def self.google_ads_conversion_id(tenant: Current.tenant)
    normalize_google_ads_conversion_id(Setting.tenant_get(GOOGLE_ADS_CONVERSION_ID_KEY, "", tenant: tenant))
  end

  def self.google_site_verification_token(tenant: Current.tenant)
    normalize_google_site_verification_token(Setting.tenant_get(GOOGLE_SITE_VERIFICATION_TOKEN_KEY, "", tenant: tenant))
  end

  def self.rd_station_enabled?(tenant: Current.tenant)
    Setting.tenant_get(RD_STATION_ENABLED_KEY, "false", tenant: tenant) == "true" && rd_station_loader_url(tenant: tenant).present?
  end

  def self.rd_station_loader_url(tenant: Current.tenant)
    normalize_rd_station_loader_url(Setting.tenant_get(RD_STATION_LOADER_URL_KEY, "", tenant: tenant))
  end

  def self.normalize_gtm_container_id(value)
    value.to_s.strip.upcase
  end

  def self.normalize_meta_pixel_id(value)
    value.to_s.gsub(/\D/, "")
  end

  def self.normalize_google_ads_conversion_id(value)
    value.to_s.strip.upcase
  end

  def self.normalize_google_site_verification_token(value)
    value.to_s.strip
  end

  def self.normalize_rd_station_loader_url(value)
    value.to_s.strip
  end

  def save
    return false unless valid?

    Setting.set(GTM_ENABLED_KEY, google_tag_manager_enabled? ? "true" : "false", "Ativa Google Tag Manager no site público", tenant: tenant)
    Setting.set(GTM_CONTAINER_ID_KEY, normalized_google_tag_manager_container_id, "ID do container Google Tag Manager", tenant: tenant)
    Setting.set(META_PIXEL_ENABLED_KEY, meta_pixel_enabled? ? "true" : "false", "Ativa Pixel da Meta no site público", tenant: tenant)
    Setting.set(META_PIXEL_ID_KEY, normalized_meta_pixel_id, "ID do Pixel da Meta", tenant: tenant)
    Setting.set(GOOGLE_ADS_ENABLED_KEY, google_ads_enabled? ? "true" : "false", "Ativa Google Ads no site público", tenant: tenant)
    Setting.set(GOOGLE_ADS_CONVERSION_ID_KEY, normalized_google_ads_conversion_id, "ID de conversão Google Ads", tenant: tenant)
    Setting.set(GOOGLE_SITE_VERIFICATION_TOKEN_KEY, normalized_google_site_verification_token, "Token de verificação Google Search Console", tenant: tenant)
    Setting.set(RD_STATION_ENABLED_KEY, rd_station_enabled? ? "true" : "false", "Ativa RD Station no site público", tenant: tenant)
    Setting.set(RD_STATION_LOADER_URL_KEY, normalized_rd_station_loader_url, "URL do loader RD Station", tenant: tenant)
    self.class.clear_cache(tenant: tenant)

    true
  end

  def self.cache_key(tenant)
    "#{CACHE_KEY}:tenant:#{tenant.id}"
  end

  def self.clear_cache(tenant: Current.tenant)
    Rails.cache.delete(cache_key(tenant)) if tenant
  end

  def google_tag_manager_enabled?
    ActiveModel::Type::Boolean.new.cast(google_tag_manager_enabled)
  end

  def meta_pixel_enabled?
    ActiveModel::Type::Boolean.new.cast(meta_pixel_enabled)
  end

  def google_ads_enabled?
    ActiveModel::Type::Boolean.new.cast(google_ads_enabled)
  end

  def rd_station_enabled?
    ActiveModel::Type::Boolean.new.cast(rd_station_enabled)
  end

  def normalized_google_tag_manager_container_id
    self.class.normalize_gtm_container_id(google_tag_manager_container_id)
  end

  def normalized_meta_pixel_id
    self.class.normalize_meta_pixel_id(meta_pixel_id)
  end

  def normalized_google_ads_conversion_id
    self.class.normalize_google_ads_conversion_id(google_ads_conversion_id)
  end

  def normalized_google_site_verification_token
    self.class.normalize_google_site_verification_token(google_site_verification_token)
  end

  def normalized_rd_station_loader_url
    self.class.normalize_rd_station_loader_url(rd_station_loader_url)
  end

  private

  def validate_google_tag_manager
    return if normalized_google_tag_manager_container_id.blank? && !google_tag_manager_enabled?

    if google_tag_manager_enabled? && normalized_google_tag_manager_container_id.blank?
      errors.add(:google_tag_manager_container_id, "não pode ficar em branco")
      return
    end

    return if normalized_google_tag_manager_container_id.match?(/\AGTM-[A-Z0-9]+\z/)

    errors.add(:google_tag_manager_container_id, "deve seguir o formato GTM-XXXXXXX")
  end

  def validate_meta_pixel
    return if normalized_meta_pixel_id.blank? && !meta_pixel_enabled?

    if meta_pixel_enabled? && normalized_meta_pixel_id.blank?
      errors.add(:meta_pixel_id, "não pode ficar em branco")
      return
    end

    return if normalized_meta_pixel_id.match?(/\A\d{5,30}\z/)

    errors.add(:meta_pixel_id, "deve conter apenas números")
  end

  def validate_google_ads
    return if normalized_google_ads_conversion_id.blank? && !google_ads_enabled?

    if google_ads_enabled? && normalized_google_ads_conversion_id.blank?
      errors.add(:google_ads_conversion_id, "não pode ficar em branco")
      return
    end

    return if normalized_google_ads_conversion_id.match?(/\AAW-\d+\z/)

    errors.add(:google_ads_conversion_id, "deve seguir o formato AW-000000000")
  end

  def validate_google_site_verification
    return if normalized_google_site_verification_token.blank?
    return if normalized_google_site_verification_token.match?(/\A[A-Za-z0-9_-]{10,120}\z/)

    errors.add(:google_site_verification_token, "deve conter apenas letras, números, hífen ou underline")
  end

  def validate_rd_station
    return if normalized_rd_station_loader_url.blank? && !rd_station_enabled?

    if rd_station_enabled? && normalized_rd_station_loader_url.blank?
      errors.add(:rd_station_loader_url, "não pode ficar em branco")
      return
    end

    uri = URI.parse(normalized_rd_station_loader_url)
    valid_loader =
      uri.is_a?(URI::HTTPS) &&
      uri.host == "d335luupugsy2.cloudfront.net" &&
      uri.path.match?(%r{\A/js/loader-scripts/[a-f0-9-]+-loader\.js\z}i)

    errors.add(:rd_station_loader_url, "deve ser uma URL oficial do loader RD Station") unless valid_loader
  rescue URI::InvalidURIError
    errors.add(:rd_station_loader_url, "deve ser uma URL válida")
  end
end
