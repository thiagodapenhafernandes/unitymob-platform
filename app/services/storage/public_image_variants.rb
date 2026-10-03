module Storage
  # Apenas anexos destinados ao site público; documentos e arquivos privados
  # nunca entram nesta publicação. O original continua intacto.
  module PublicImageVariants
    HERO = [[640, 1138], [900, 1600], [1440, 810], [1920, 1080]].map do |size|
      { resize_to_limit: size, format: :webp, quality: 82, strip: true }
    end.freeze
    CARD = [[360, 270], [540, 405], [720, 540]].map do |size|
      { resize_to_fill: size, format: :webp }
    end.freeze
    BANNER = [[1440, 360], [768, 360]].map do |size|
      { resize_to_limit: size, format: :webp, quality: 82, strip: true }
    end.freeze
    ATTACHMENTS = {
      "HomeHeroSlide" => %w[image],
      "HomeSetting" => %w[hero_background_desktop hero_background_mobile],
      "Banner" => %w[image_desktop image_mobile],
      "Habitation" => %w[photos watermark_photos]
    }.freeze

    def self.define(attachment, transformations)
      transformations.each_with_index do |options, index|
        attachment.variant :"public_web_#{index}", **options, preprocessed: true
      end
    end

    def self.publish(blob, transformations)
      return unless (HERO + CARD + BANNER).include?(transformations.deep_symbolize_keys)
      attachment = blob.attachments.detect do |item|
        ATTACHMENTS.fetch(item.record_type, []).include?(item.name)
      end
      return unless attachment

      record = attachment.record
      tenant = record.respond_to?(:tenant) ? record.tenant : record.home_setting.tenant
      return unless Storage::PublicPropertyPhoto.public_photos_enabled?(tenant: tenant)

      variant_blob = blob.variant(**transformations.deep_symbolize_keys).image.blob
      return if variant_blob.metadata["public_web_image"]
      return unless Storage::PublicPropertyPhoto.publish_blob!(variant_blob)

      variant_blob.update!(metadata: variant_blob.metadata.merge("public_web_image" => true))
    end
  end
end
