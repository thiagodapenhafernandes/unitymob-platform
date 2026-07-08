class TrackingIntegrationSetting
  include ActiveModel::Model
  include ActiveModel::Attributes

  PREFIX = "tracking".freeze

  GTM_ENABLED_KEY = "#{PREFIX}.google_tag_manager.enabled".freeze
  GTM_CONTAINER_ID_KEY = "#{PREFIX}.google_tag_manager.container_id".freeze
  META_PIXEL_ENABLED_KEY = "#{PREFIX}.meta_pixel.enabled".freeze
  META_PIXEL_ID_KEY = "#{PREFIX}.meta_pixel.pixel_id".freeze
  CACHE_KEY = "public_site:tracking_integration_setting".freeze

  HUMAN_ATTRIBUTES = {
    "google_tag_manager_enabled" => "Google Tag Manager ativo",
    "google_tag_manager_container_id" => "ID do container GTM",
    "meta_pixel_enabled" => "Pixel da Meta ativo",
    "meta_pixel_id" => "ID do Pixel da Meta"
  }.freeze

  attribute :google_tag_manager_enabled, :boolean, default: false
  attribute :google_tag_manager_container_id, :string
  attribute :meta_pixel_enabled, :boolean, default: false
  attribute :meta_pixel_id, :string

  validate :validate_google_tag_manager
  validate :validate_meta_pixel

  def self.current
    Rails.cache.fetch(CACHE_KEY, expires_in: 5.minutes) do
      build_current
    end
  end

  def self.build_current
    new(
      google_tag_manager_enabled: Setting.get(GTM_ENABLED_KEY, "false") == "true",
      google_tag_manager_container_id: Setting.get(GTM_CONTAINER_ID_KEY, ""),
      meta_pixel_enabled: Setting.get(META_PIXEL_ENABLED_KEY, "false") == "true",
      meta_pixel_id: Setting.get(META_PIXEL_ID_KEY, "")
    )
  end

  def self.human_attribute_name(attribute, options = {})
    HUMAN_ATTRIBUTES[attribute.to_s] || super
  end

  def self.google_tag_manager_enabled?
    Setting.get(GTM_ENABLED_KEY, "false") == "true" && google_tag_manager_container_id.present?
  end

  def self.google_tag_manager_container_id
    normalize_gtm_container_id(Setting.get(GTM_CONTAINER_ID_KEY, ""))
  end

  def self.meta_pixel_enabled?
    Setting.get(META_PIXEL_ENABLED_KEY, "false") == "true" && meta_pixel_id.present?
  end

  def self.meta_pixel_id
    normalize_meta_pixel_id(Setting.get(META_PIXEL_ID_KEY, ""))
  end

  def self.normalize_gtm_container_id(value)
    value.to_s.strip.upcase
  end

  def self.normalize_meta_pixel_id(value)
    value.to_s.gsub(/\D/, "")
  end

  def save
    return false unless valid?

    Setting.set(GTM_ENABLED_KEY, google_tag_manager_enabled? ? "true" : "false", "Ativa Google Tag Manager no site público")
    Setting.set(GTM_CONTAINER_ID_KEY, normalized_google_tag_manager_container_id, "ID do container Google Tag Manager")
    Setting.set(META_PIXEL_ENABLED_KEY, meta_pixel_enabled? ? "true" : "false", "Ativa Pixel da Meta no site público")
    Setting.set(META_PIXEL_ID_KEY, normalized_meta_pixel_id, "ID do Pixel da Meta")
    self.class.clear_cache

    true
  end

  def self.clear_cache
    Rails.cache.delete(CACHE_KEY)
  end

  def google_tag_manager_enabled?
    ActiveModel::Type::Boolean.new.cast(google_tag_manager_enabled)
  end

  def meta_pixel_enabled?
    ActiveModel::Type::Boolean.new.cast(meta_pixel_enabled)
  end

  def normalized_google_tag_manager_container_id
    self.class.normalize_gtm_container_id(google_tag_manager_container_id)
  end

  def normalized_meta_pixel_id
    self.class.normalize_meta_pixel_id(meta_pixel_id)
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
end
