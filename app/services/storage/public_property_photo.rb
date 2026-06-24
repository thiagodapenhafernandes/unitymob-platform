require "cgi"

module Storage
  module PublicPropertyPhoto
    module_function

    def public_attachment?(attachment)
      return false unless defined?(ActiveStorage::Attachment)
      return false unless attachment.is_a?(ActiveStorage::Attachment)
      return false unless public_photos_enabled?

      property_photo_attachment?(attachment)
    end

    def public_url_for_attachment(attachment)
      return unless public_attachment?(attachment)

      public_url_for_blob(attachment.blob)
    end

    def public_url_for_blob(blob)
      base_url = public_base_url(blob)
      return if base_url.blank? || blob.blank? || blob.key.blank?
      return unless s3_blob?(blob)

      "#{base_url}/#{escaped_key(blob.key)}"
    end

    def publish_attachment!(attachment)
      return false unless public_attachment?(attachment)

      publish_blob!(attachment.blob)
    end

    def publish_blob!(blob, raise_errors: false)
      return false unless blob
      return false unless s3_blob?(blob)

      blob.service.send(:object_for, blob.key).acl.put(acl: "public-read")
      true
    rescue StandardError => e
      raise if raise_errors

      Rails.logger.warn("[public_property_photo] blob_id=#{blob&.id} key=#{blob&.key} error=#{e.class}: #{e.message}")
      false
    end

    def public_base_url(blob = nil)
      configured = configured_public_base_url(blob)
      return configured if configured.present?

      raw = ENV["DO_SPACES_PUBLIC_BASE_URL"].presence ||
            normalized_cdn_env_url ||
            default_cdn_base_url

      raw.to_s.sub(%r{/\z}, "").presence
    end

    def configured_public_base_url(blob)
      return unless defined?(StorageIntegrationSetting)
      return if blob.blank?

      StorageIntegrationSetting.current.public_base_url_for_service_name(blob.service_name)
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::PendingMigrationError
      nil
    end

    def public_photos_enabled?
      return true unless defined?(StorageIntegrationSetting)

      StorageIntegrationSetting.current.public_photos_enabled?
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::PendingMigrationError
      true
    end

    def normalized_cdn_env_url
      raw = ENV["DO_SPACES_CDN_URL"].presence
      return if raw.blank?

      normalize_spaces_cdn_url(raw)
    end

    def normalize_spaces_cdn_url(raw)
      raw.to_s
        .sub(%r{/\z}, "")
        .sub(%r{\A(https?://)([^./]+)\.([a-z0-9-]+)\.digitaloceanspaces\.com\z}i, '\1\2.\3.cdn.digitaloceanspaces.com')
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
