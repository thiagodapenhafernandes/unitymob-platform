require "cgi"
require "net/http"

module Storage
  module PublicPropertyPhoto
    module_function

    def public_attachment?(attachment)
      return false unless defined?(ActiveStorage::Attachment)
      return false unless attachment.is_a?(ActiveStorage::Attachment)
      return false unless public_photos_enabled?(tenant: attachment_tenant(attachment))

      property_photo_attachment?(attachment)
    end

    def public_url_for_attachment(attachment)
      return unless public_attachment?(attachment)

      public_url_for_blob(attachment.blob, tenant: attachment_tenant(attachment))
    end

    def public_url_for_blob(blob, tenant: Current.tenant)
      return if blob.blank? || blob.key.blank?
      return unless s3_blob?(blob)

      # Serviços legados mantêm o bucket original, mesmo após trocar o
      # armazenamento configurado da conta. Não misture os dois endereços.
      if StorageIntegrationSetting::LEGACY_DO_SERVICE_NAMES.include?(blob.service_name.to_sym)
        url = blob.service.send(:object_for, blob.key).public_url
        return blob.metadata["public_web_cdn"] ? normalize_spaces_cdn_url(url) : url
      end

      base_url = public_base_url(blob, tenant: tenant)
      return if base_url.blank?

      "#{base_url}/#{escaped_key(blob.key)}"
    end

    def publish_attachment!(attachment)
      return false unless public_attachment?(attachment)

      publish_blob!(attachment.blob)
    end

    def publish_blob!(blob, raise_errors: false)
      return false unless blob
      return false unless s3_blob?(blob)

      if Rails.env.development? && blob.service_name != "development_sandbox"
        raise IOError, "Publicação bloqueada no armazenamento de origem"
      end

      blob.service.send(:object_for, blob.key).acl.put(acl: "public-read")
      true
    rescue StandardError => e
      raise if raise_errors

      Rails.logger.warn("[public_property_photo] blob_id=#{blob&.id} key=#{blob&.key} error=#{e.class}: #{e.message}")
      false
    end

    # Uma origem Spaces pode existir sem CDN habilitado. Verifique no job,
    # nunca durante a renderização; mantenha a origem se o CDN falhar.
    def public_cdn_available?(blob)
      return false unless StorageIntegrationSetting::LEGACY_DO_SERVICE_NAMES.include?(blob.service_name.to_sym)

      url = normalize_spaces_cdn_url(blob.service.send(:object_for, blob.key).public_url)
      uri = URI.parse(url)
      return false unless uri.scheme == "https" && uri.host.to_s.end_with?(".cdn.digitaloceanspaces.com")

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 3) do |http|
        http.head(uri.request_uri).is_a?(Net::HTTPSuccess)
      end
    rescue StandardError
      false
    end

    # Apenas derivadas já publicadas, com chave imutável. Preserva os metadados.
    def cache_public_blob!(blob)
      object = blob.service.send(:object_for, blob.key)
      object.copy_from(
        copy_source: "#{object.bucket_name}/#{Storage::PublicPropertyPhoto.escaped_key(blob.key)}",
        metadata_directive: "REPLACE", metadata: object.metadata,
        content_type: object.content_type, content_disposition: object.content_disposition,
        cache_control: "public, max-age=31536000, immutable", acl: "public-read"
      )
    end

    def public_base_url(blob = nil, tenant: Current.tenant)
      if Rails.env.development? && blob&.service_name == "development_sandbox"
        region = ENV.fetch("DO_SPACES_REGION", "sfo3")
        return "https://unitymob-development-media.#{region}.digitaloceanspaces.com"
      end

      configured = configured_public_base_url(blob, tenant: tenant)
      return configured if configured.present?

      raw = env_public_base_url(tenant)

      raw.to_s.sub(%r{/\z}, "").presence
    end

    def configured_public_base_url(blob, tenant: Current.tenant)
      return unless defined?(StorageIntegrationSetting)
      return if blob.blank?

      StorageIntegrationSetting.current(tenant: tenant).public_base_url_for_service_name(blob.service_name)
    rescue ArgumentError, ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::PendingMigrationError
      nil
    end

    def public_photos_enabled?(tenant: Current.tenant)
      return true unless defined?(StorageIntegrationSetting)

      StorageIntegrationSetting.current(tenant: tenant).public_photos_enabled?
    rescue ArgumentError, ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::PendingMigrationError
      false
    end

    def attachment_tenant(attachment)
      attachment.record.respond_to?(:tenant) ? attachment.record.tenant : Current.tenant
    end

    def env_public_base_url(tenant)
      return unless StorageIntegrationSetting.environment_defaults_allowed?(tenant)

      ENV["DO_SPACES_PUBLIC_BASE_URL"].presence ||
        normalized_cdn_env_url ||
        default_cdn_base_url
    end

    def normalized_cdn_env_url
      raw = ENV["DO_SPACES_CDN_URL"].presence
      return if raw.blank?

      normalize_spaces_cdn_url(raw)
    end

    def normalize_spaces_cdn_url(raw)
      raw.to_s
        .sub(%r{/\z}, "")
        .sub(%r{\A(https?://)([^./]+)\.([a-z0-9-]+)\.digitaloceanspaces\.com(?=/|\z)}i, '\1\2.\3.cdn.digitaloceanspaces.com')
    end

    def default_cdn_base_url
      bucket = ENV["DO_SPACES_BUCKET"].presence
      region = ENV.fetch("DO_SPACES_REGION", "sfo3")
      return if bucket.blank?

      "https://#{bucket}.#{region}.cdn.digitaloceanspaces.com"
    end

    def escaped_key(key)
      key.to_s.split("/").map { |segment| CGI.escape(segment).gsub("+", "%20") }.join("/")
    end

    def s3_blob?(blob)
      return false unless defined?(ActiveStorage::Service::S3Service)

      blob.service.is_a?(ActiveStorage::Service::S3Service)
    rescue KeyError
      return false unless defined?(Storage::ActiveStorageRegistry)

      Storage::ActiveStorageRegistry.fetch!(blob.service_name)
      blob.service.is_a?(ActiveStorage::Service::S3Service)
    end

    def property_photo_attachment?(attachment)
      attachment.record_type == "Habitation" && attachment.name == "photos"
    end
  end
end
