require "set"

module Habitations
  class MediaGallery
    def initialize(habitation)
      @habitation = habitation
    end

    def locals
      {
        habitation: habitation,
        linked_development: linked_development,
        attached_media_photos: attached_media_photos,
        api_media_pictures: api_media_pictures
      }
    end

    def attached_media_photos
      @attached_media_photos ||= if habitation.photos.attached?
        habitation.ordered_photos.select { |photo| photo.persisted? && photo.blob&.persisted? }
      else
        []
      end
    end

    def api_media_pictures
      @api_media_pictures ||= raw_api_media_pictures.reject do |pic, original_index, pic_url|
        covered_by_attached_media?(pic, original_index, pic_url)
      end
    end

    def media_gallery_count
      attached_media_photos.size + api_media_pictures.size + development_fallback_count
    end

    def linked_development
      @linked_development ||= habitation.empreendimento if habitation.codigo_empreendimento.present?
    end

    def development_fallback_count
      return 0 unless habitation.use_development_photos?
      return 0 unless linked_development.present?
      return 0 if habitation.own_public_image_sources.present?

      linked_development.own_public_image_sources.first(12).size
    end

    private

    attr_reader :habitation

    def raw_api_media_pictures
      return [] unless habitation.pictures.is_a?(Array)

      habitation.pictures.each_with_index.filter_map do |pic, index|
        pic_url = picture_url(pic)
        [pic, index, pic_url] if pic_url.present?
      end
    end

    def covered_by_attached_media?(pic, original_index, pic_url)
      return false if attached_media_photos.blank?

      (picture_identity_keys(pic, pic_url) & attached_media_identity_keys).any?
    end

    def attached_media_identity_keys
      @attached_media_identity_keys ||= attached_media_photos.flat_map do |attachment|
        keys = [attachment.filename.to_s]
        metadata = attachment.blob&.metadata.to_h
        keys << metadata["vista_source_url"]
        keys << source_path_from_url(metadata["vista_source_url"])
        keys << metadata["source_url"]
        keys << source_path_from_url(metadata["source_url"])
        keys.compact_blank.map { |key| normalize_identity_key(key) }
      end.to_set
    end

    def picture_identity_keys(pic, pic_url)
      keys = [pic_url, source_path_from_url(pic_url), filename_from_url(pic_url)]

      if pic.respond_to?(:[])
        keys << pic["codigo_midia_vista"]
        keys << pic[:codigo_midia_vista]
        keys << pic["imagem_codigo"]
        keys << pic[:imagem_codigo]
        keys << pic["Codigo"]
        keys << pic[:Codigo]
        keys << pic["ImagemCodigo"]
        keys << pic[:ImagemCodigo]
      end

      keys.compact_blank.map { |key| normalize_identity_key(key) }.to_set
    end

    def picture_url(pic)
      return pic.to_s if pic.is_a?(String)
      return unless pic.respond_to?(:[])

      pic["url"].presence ||
        pic[:url].presence ||
        pic["src"].presence ||
        pic[:src].presence ||
        pic["link"].presence ||
        pic[:link].presence ||
        pic["Foto"].presence ||
        pic[:Foto].presence ||
        pic["FotoOriginal"].presence ||
        pic[:FotoOriginal].presence ||
        pic["FotoPequena"].presence ||
        pic[:FotoPequena].presence
    end

    def source_path_from_url(url)
      URI.parse(url.to_s).path.to_s.delete_prefix("/")
    rescue URI::InvalidURIError
      nil
    end

    def filename_from_url(url)
      File.basename(URI.parse(url.to_s).path)
    rescue URI::InvalidURIError
      File.basename(url.to_s.split("?").first)
    end

    def normalize_identity_key(value)
      value.to_s.strip.downcase
    end
  end
end
