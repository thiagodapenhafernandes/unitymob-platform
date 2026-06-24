require "uri"

module Storage
  class PublicCdnImageUrl
    SOURCE_URL_KEYS = [
      "url",
      :url,
      "url_pequena",
      :url_pequena,
      "url_small",
      :url_small,
      "thumbnail_url",
      :thumbnail_url,
      "url_original",
      :url_original,
      "src",
      :src,
      "link",
      :link,
      "Foto",
      :Foto,
      "FotoOriginal",
      :FotoOriginal,
      "FotoPequena",
      :FotoPequena
    ].freeze

    def self.resolve(source = nil, **options)
      source ||= options if options.present?

      new(source).resolve
    end

    def initialize(source)
      @source = source
    end

    def resolve
      return if source.blank?

      attachment = attachment_from_source
      return cdn_url_for_attachment(attachment) if attachment

      blob = blob_from_source
      return cdn_url_for_blob(blob) if blob

      cdn_url_from_source
    end

    private

    attr_reader :source

    def attachment_from_source
      attachment = hash_value("attachment") || hash_value(:attachment)
      return attachment if active_storage_attachment?(attachment)

      return source if active_storage_attachment?(source)

      if source.respond_to?(:attached?) && source.attached?
        source.attachment
      end
    end

    def blob_from_source
      blob = hash_value("blob") || hash_value(:blob)
      return blob if active_storage_blob?(blob)
      return source if active_storage_blob?(source)
    end

    def cdn_url_for_attachment(attachment)
      return if attachment.blank?

      Storage::PublicPropertyPhoto.public_url_for_attachment(attachment) ||
        cdn_url_for_blob(attachment.blob)
    rescue StandardError
      nil
    end

    def cdn_url_for_blob(blob)
      Storage::PublicPropertyPhoto.public_url_for_blob(blob)
    rescue StandardError
      nil
    end

    def cdn_url_from_source
      url = source_url
      return if url.blank?

      value = url.to_s.strip
      return if value.blank? || value.start_with?("#<", "/", "data:", "blob:")

      uri = URI.parse(value)
      return unless uri.is_a?(URI::HTTP)
      return unless cdn_hosts.include?(uri.host.to_s.downcase)

      value
    rescue URI::InvalidURIError
      nil
    end

    def source_url
      return source if source.is_a?(String)
      return unless source.is_a?(Hash)

      SOURCE_URL_KEYS.each do |key|
        value = hash_value(key)
        return value if value.present?
      end

      nil
    end

    def cdn_hosts
      @cdn_hosts ||= [
        Storage::PublicPropertyPhoto.public_base_url,
        ENV["DO_SPACES_PUBLIC_BASE_URL"]
      ].filter_map { |url| host_from_url(url) }.uniq
    end

    def host_from_url(url)
      return if url.blank?

      URI.parse(url.to_s).host&.downcase
    rescue URI::InvalidURIError
      nil
    end

    def active_storage_attachment?(value)
      defined?(ActiveStorage::Attachment) && value.is_a?(ActiveStorage::Attachment)
    end

    def active_storage_blob?(value)
      defined?(ActiveStorage::Blob) && value.is_a?(ActiveStorage::Blob)
    end

    def hash_value(key)
      source[key] if source.is_a?(Hash)
    end
  end
end
