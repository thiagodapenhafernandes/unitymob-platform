class StorageIntegrationSetting < ApplicationRecord
  belongs_to :tenant

  CURRENT_CACHE_KEY = :storage_integration_setting_current

  PROVIDERS = %w[local digital_ocean amazon_s3].freeze
  PROVIDER_LABELS = {
    "local" => "Local",
    "digital_ocean" => "DigitalOcean Spaces",
    "amazon_s3" => "Amazon S3"
  }.freeze

  DO_SERVICE_NAME = :do_spaces_db
  S3_SERVICE_NAME = :amazon_s3_db
  LEGACY_DO_SERVICE_NAMES = [:do_spaces].freeze
  LEGACY_S3_SERVICE_NAMES = [:amazon, :amazon_s3].freeze

  validates :photo_provider, :document_provider, inclusion: { in: PROVIDERS }
  validates :do_spaces_region, :do_spaces_endpoint, presence: true
  validates :s3_region, presence: true
  validate :validate_provider_configuration
  after_commit :clear_current_cache

  def self.instance(tenant: Current.tenant)
    raise ArgumentError, "Tenant obrigatório para armazenamento" unless tenant

    find_by(tenant: tenant) || create_from_environment!(tenant: tenant)
  end

  def self.current(tenant: Current.tenant)
    instance(tenant: tenant)
  end

  def self.clear_current_cache
    nil
  end

  def self.create_from_environment!(tenant:)
    create!(defaults_from_environment.merge(tenant: tenant))
  end

  def self.defaults_from_environment
    active_service = Rails.configuration.active_storage.service.to_s
    do_provider = "digital_ocean" if active_service == "do_spaces" && digital_ocean_environment_ready?
    s3_provider = "amazon_s3" if %w[amazon amazon_s3].include?(active_service) && amazon_environment_ready?
    default_provider = do_provider || s3_provider || "local"

    {
      photo_provider: default_provider,
      document_provider: default_provider,
      public_photos_enabled: true,
      do_spaces_bucket: ENV["DO_SPACES_BUCKET"],
      do_spaces_region: ENV.fetch("DO_SPACES_REGION", "sfo3"),
      do_spaces_endpoint: ENV.fetch("DO_SPACES_ENDPOINT", "https://sfo3.digitaloceanspaces.com"),
      do_spaces_public_base_url: ENV["DO_SPACES_PUBLIC_BASE_URL"],
      do_spaces_access_key_id: ENV["DO_SPACES_ACCESS_KEY_ID"],
      do_spaces_secret_access_key: ENV["DO_SPACES_SECRET_ACCESS_KEY"],
      s3_bucket: ENV["AWS_S3_BUCKET"].presence || ENV["S3_BUCKET"].presence,
      s3_region: ENV.fetch("AWS_REGION", ENV.fetch("S3_REGION", "us-east-1")),
      s3_endpoint: ENV["AWS_S3_ENDPOINT"].presence || ENV["S3_ENDPOINT"].presence,
      s3_public_base_url: ENV["AWS_S3_PUBLIC_BASE_URL"].presence || ENV["S3_PUBLIC_BASE_URL"].presence,
      s3_access_key_id: ENV["AWS_ACCESS_KEY_ID"].presence || ENV["S3_ACCESS_KEY_ID"].presence,
      s3_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"].presence || ENV["S3_SECRET_ACCESS_KEY"].presence
    }.compact
  end

  def self.digital_ocean_environment_ready?
    ENV["DO_SPACES_BUCKET"].present? &&
      ENV["DO_SPACES_ACCESS_KEY_ID"].present? &&
      ENV["DO_SPACES_SECRET_ACCESS_KEY"].present?
  end

  def self.amazon_environment_ready?
    (ENV["AWS_S3_BUCKET"].present? || ENV["S3_BUCKET"].present?) &&
      (ENV["AWS_ACCESS_KEY_ID"].present? || ENV["S3_ACCESS_KEY_ID"].present?) &&
      (ENV["AWS_SECRET_ACCESS_KEY"].present? || ENV["S3_SECRET_ACCESS_KEY"].present?)
  end

  def self.provider_options
    PROVIDERS.map { |provider| [PROVIDER_LABELS.fetch(provider), provider] }
  end

  def do_spaces_access_key_id
    decrypt_secret(do_spaces_access_key_id_ciphertext)
  end

  def do_spaces_access_key_id=(value)
    assign_encrypted_secret(:do_spaces_access_key_id_ciphertext, value)
  end

  def do_spaces_secret_access_key
    decrypt_secret(do_spaces_secret_access_key_ciphertext)
  end

  def do_spaces_secret_access_key=(value)
    assign_encrypted_secret(:do_spaces_secret_access_key_ciphertext, value)
  end

  def s3_access_key_id
    decrypt_secret(s3_access_key_id_ciphertext)
  end

  def s3_access_key_id=(value)
    assign_encrypted_secret(:s3_access_key_id_ciphertext, value)
  end

  def s3_secret_access_key
    decrypt_secret(s3_secret_access_key_ciphertext)
  end

  def s3_secret_access_key=(value)
    assign_encrypted_secret(:s3_secret_access_key_ciphertext, value)
  end

  def secret_configured?(attribute)
    public_send("#{attribute}_ciphertext").present?
  end

  def photo_service_name
    service_name_for_provider(photo_provider)
  end

  def document_service_name
    service_name_for_provider(document_provider)
  end

  def service_name_for_provider(provider)
    case provider.to_s
    when "digital_ocean" then tenant_service_name(DO_SERVICE_NAME)
    when "amazon_s3" then tenant_service_name(S3_SERVICE_NAME)
    else :local
    end
  end

  def provider_for_service_name(service_name)
    case service_name.to_s
    when "do_spaces", DO_SERVICE_NAME.to_s, tenant_service_name(DO_SERVICE_NAME).to_s then "digital_ocean"
    when "amazon", "amazon_s3", S3_SERVICE_NAME.to_s, tenant_service_name(S3_SERVICE_NAME).to_s then "amazon_s3"
    else "local"
    end
  end

  def public_base_url_for_service_name(service_name)
    case provider_for_service_name(service_name)
    when "digital_ocean" then digital_ocean_public_base_url
    when "amazon_s3" then amazon_public_base_url
    end
  end

  def active_storage_configurations
    configs = {}

    if digital_ocean_ready?
      config = digital_ocean_service_config
      configs[tenant_service_name(DO_SERVICE_NAME)] = config
    end

    if amazon_ready?
      config = amazon_service_config
      configs[tenant_service_name(S3_SERVICE_NAME)] = config
    end

    configs
  end

  def digital_ocean_ready?
    do_spaces_bucket.present? &&
      do_spaces_region.present? &&
      do_spaces_endpoint.present? &&
      do_spaces_access_key_id.present? &&
      do_spaces_secret_access_key.present?
  end

  def amazon_ready?
    s3_bucket.present? &&
      s3_region.present? &&
      s3_access_key_id.present? &&
      s3_secret_access_key.present?
  end

  def test_ready_for?(provider)
    case provider.to_s
    when "local" then true
    when "digital_ocean" then digital_ocean_ready?
    when "amazon_s3" then amazon_ready?
    else false
    end
  end

  def mark_test!(status:, message:)
    update_columns(
      last_tested_at: Time.current,
      last_test_status: status.to_s,
      last_test_message: message.to_s.truncate(1_000),
      updated_at: Time.current
    )
    self.class.clear_current_cache
  end

  private

  def tenant_service_name(base_name)
    "#{base_name}_tenant_#{tenant_id}".to_sym
  end

  def clear_current_cache
    self.class.clear_current_cache
  end

  def validate_provider_configuration
    add_provider_errors(:photo_provider, photo_provider)
    add_provider_errors(:document_provider, document_provider)
  end

  def add_provider_errors(attribute, provider)
    return if provider == "local"
    return if provider == "digital_ocean" && digital_ocean_ready?
    return if provider == "amazon_s3" && amazon_ready?

    errors.add(attribute, "precisa de credenciais e bucket configurados")
  end

  def digital_ocean_service_config
    {
      service: "S3",
      access_key_id: do_spaces_access_key_id,
      secret_access_key: do_spaces_secret_access_key,
      region: do_spaces_region,
      endpoint: do_spaces_endpoint,
      bucket: do_spaces_bucket,
      force_path_style: false
    }
  end

  def amazon_service_config
    {
      service: "S3",
      access_key_id: s3_access_key_id,
      secret_access_key: s3_secret_access_key,
      region: s3_region,
      bucket: s3_bucket,
      endpoint: s3_endpoint.presence,
      force_path_style: false
    }.compact
  end

  def digital_ocean_public_base_url
    raw = do_spaces_public_base_url.presence ||
      "https://#{do_spaces_bucket}.#{do_spaces_region}.cdn.digitaloceanspaces.com"

    normalize_public_url(raw)
  end

  def amazon_public_base_url
    raw = s3_public_base_url.presence ||
      "https://#{s3_bucket}.s3.#{s3_region}.amazonaws.com"

    normalize_public_url(raw)
  end

  def normalize_public_url(value)
    value.to_s.sub(%r{/\z}, "").presence
  end

  def assign_encrypted_secret(attribute, value)
    return if value.to_s.blank?

    self[attribute] = self.class.encrypt_secret(value.to_s.strip)
  end

  def decrypt_secret(ciphertext)
    return if ciphertext.blank?

    self.class.encryptor.decrypt_and_verify(ciphertext)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def self.encrypt_secret(value)
    encryptor.encrypt_and_sign(value)
  end

  def self.encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key(
      "storage-integration-setting",
      ActiveSupport::MessageEncryptor.key_len
    )
    ActiveSupport::MessageEncryptor.new(key)
  end
end
