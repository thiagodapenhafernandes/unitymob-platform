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

    # Chaves de feed que apontam para versões reduzidas da foto — preferidas
    # quando a view pede resize (comportamento pré-unificação do resolver).
    SMALL_SOURCE_URL_KEYS = [
      "url_pequena",
      :url_pequena,
      "url_small",
      :url_small,
      "thumbnail_url",
      :thumbnail_url,
      "FotoPequena",
      :FotoPequena
    ].freeze

    TRANSFORMATION_KEYS = %i[resize_to_limit resize_to_fill].freeze
    TRUSTED_EXTERNAL_IMAGE_HOSTS = [
      "dwvimagesv1.b-cdn.net"
    ].freeze

    def self.resolve(source = nil, **options)
      source ||= options if options.present?

      new(source, **options).resolve
    end

    def initialize(source, **options)
      @source = source
      @options = options
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

    attr_reader :source, :options

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

      variant_url_for(attachment.blob) ||
        Storage::PublicPropertyPhoto.public_url_for_attachment(attachment) ||
        original_cdn_url_for_blob(attachment.blob)
    rescue StandardError
      nil
    end

    def cdn_url_for_blob(blob)
      variant_url_for(blob) || original_cdn_url_for_blob(blob)
    rescue StandardError
      nil
    end

    def original_cdn_url_for_blob(blob)
      Storage::PublicPropertyPhoto.public_url_for_blob(blob)
    rescue StandardError
      nil
    end

    # Quando a view pede resize, serve o variant já processado via rota de
    # representation (URL assinada; dispensa ACL pública no bucket para o blob
    # do variant). Variants ainda não processados são enfileirados
    # (ActiveStorage::TransformJob) e a URL original do CDN segue sendo servida
    # até o processamento concluir — nunca processa imagem no request.
    def variant_url_for(blob)
      return if blob.blank?
      return unless variant_requested?
      return unless blob.respond_to?(:variable?) && blob.variable?

      variant = blob.variant(**variant_transformations)
      return representation_path(variant) if variant_processed?(variant)

      enqueue_variant_processing(blob)
      nil
    rescue StandardError => e
      Rails.logger.warn("[public_cdn_image_url] variant fallback blob_id=#{blob&.id} error=#{e.class}: #{e.message}")
      nil
    end

    def variant_requested?
      variant_transformations.present?
    end

    def variant_transformations
      @variant_transformations ||= begin
        transformations = options.slice(*TRANSFORMATION_KEYS).compact
        saver = options[:saver]
        transformations[:saver] = saver if transformations.present? && saver.present?
        transformations
      end
    end

    def variant_processed?(variant)
      variant.respond_to?(:processed?, true) && variant.send(:processed?)
    end

    def representation_path(variant)
      Rails.application.routes.url_helpers.rails_representation_path(variant)
    end

    def enqueue_variant_processing(blob)
      return unless defined?(ActiveStorage::TransformJob)

      digest = ActiveStorage::Variation.wrap(variant_transformations).digest
      guard_key = "storage/public_cdn_image_url/transform/#{blob.id}/#{digest}"
      return unless Rails.cache.write(guard_key, "1", unless_exist: true, expires_in: 15.minutes)

      ActiveStorage::TransformJob.perform_later(blob, variant_transformations)
    rescue StandardError => e
      Rails.logger.warn("[public_cdn_image_url] transform enqueue blob_id=#{blob&.id} error=#{e.class}: #{e.message}")
      nil
    end

    def cdn_url_from_source
      candidate_source_urls.each do |candidate|
        value = validated_cdn_url(candidate)
        return value if value.present?
      end

      nil
    end

    def candidate_source_urls
      return [source] if source.is_a?(String)
      return [] unless source.is_a?(Hash)

      keys = variant_requested? ? SMALL_SOURCE_URL_KEYS + SOURCE_URL_KEYS : SOURCE_URL_KEYS
      values = keys.filter_map { |key| hash_value(key).presence }.uniq

      # Sem resize preserva o comportamento original: só o primeiro valor presente.
      variant_requested? ? values : values.first(1)
    end

    def validated_cdn_url(url)
      value = url.to_s.strip
      return if value.blank? || value.start_with?("#<", "/", "data:", "blob:")

      uri = URI.parse(value)
      return unless uri.is_a?(URI::HTTP)
      return unless allowed_image_hosts.include?(uri.host.to_s.downcase)

      value
    rescue URI::InvalidURIError
      nil
    end

    def allowed_image_hosts
      @allowed_image_hosts ||= (
        [
        Storage::PublicPropertyPhoto.public_base_url,
        ENV["DO_SPACES_PUBLIC_BASE_URL"]
        ].filter_map { |url| host_from_url(url) } +
        trusted_external_image_hosts
      ).uniq
    end

    def trusted_external_image_hosts
      env_hosts = ENV.fetch("TRUSTED_EXTERNAL_IMAGE_HOSTS", "").split(",")

      (TRUSTED_EXTERNAL_IMAGE_HOSTS + env_hosts)
        .map { |host| host.to_s.strip.downcase }
        .reject(&:blank?)
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
