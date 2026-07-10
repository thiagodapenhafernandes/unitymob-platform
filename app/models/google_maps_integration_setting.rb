class GoogleMapsIntegrationSetting < ApplicationRecord
  include EncryptionAvailability

  DISPLAY_MODES = %w[hidden approximate exact].freeze
  DEFAULT_DISPLAY_MODE = "approximate".freeze
  DEFAULT_RADIUS_METERS = 220
  MIN_RADIUS_METERS = 100
  MAX_RADIUS_METERS = 2_000
  DEFAULT_ZOOM = 15
  MIN_ZOOM = 10
  MAX_ZOOM = 20

  belongs_to :tenant

  encrypts :api_key

  validates :tenant_id, uniqueness: true
  validates :default_display_mode, inclusion: { in: DISPLAY_MODES }
  validates :approximate_radius_meters,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: MIN_RADIUS_METERS,
              less_than_or_equal_to: MAX_RADIUS_METERS
            }
  validates :default_zoom,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: MIN_ZOOM,
              less_than_or_equal_to: MAX_ZOOM
            }
  validate :validate_required_fields_when_enabled

  before_validation :normalize_values

  def self.for(tenant)
    raise ArgumentError, "Tenant obrigatório para configurar Google Maps" if tenant.blank?

    where(tenant: tenant).first_or_initialize(
      default_display_mode: DEFAULT_DISPLAY_MODE,
      approximate_radius_meters: DEFAULT_RADIUS_METERS,
      default_zoom: DEFAULT_ZOOM,
      satellite_enabled: true,
      street_view_enabled: true,
      external_link_enabled: true
    )
  end

  def configured?
    enabled? && encryption_ready? && api_key_configured?
  end

  def api_key_configured?
    return false unless encryption_ready?

    api_key.present?
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  def missing_configuration_items
    items = []
    items << "criptografia do servidor (AR_ENCRYPTION_*)" unless encryption_ready?
    items << "chave da API" unless api_key_configured?
    items
  end

  private

  def normalize_values
    self.api_key = api_key.to_s.strip.presence if api_key_changed?
    self.default_display_mode = default_display_mode.to_s.strip.presence || DEFAULT_DISPLAY_MODE
    self.approximate_radius_meters = approximate_radius_meters.to_i if approximate_radius_meters.present?
    self.default_zoom = default_zoom.to_i if default_zoom.present?
  end

  def validate_required_fields_when_enabled
    return unless enabled?

    errors.add(:base, "Configure as chaves AR_ENCRYPTION_* antes de salvar a chave do Google Maps.") unless encryption_ready?
    errors.add(:api_key, "não pode ficar em branco") unless api_key_configured?
  end
end
