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
        api_media_pictures: api_media_pictures,
        development_media_sources: development_media_sources
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
      @api_media_pictures ||= raw_dwv_pictures.reject do |pic, _original_index, pic_url|
        covered_by_attached_media?(pic_url)
      end
    end

    def media_gallery_count
      attached_media_photos.size + api_media_pictures.size + development_media_sources.size
    end

    def linked_development
      @linked_development ||= habitation.empreendimento if habitation.codigo_empreendimento.present?
    end

    def development_media_sources
      @development_media_sources ||= if habitation.use_development_photos? && linked_development.present?
        linked_development.own_public_image_sources.first(12)
      else
        []
      end
    end

    private

    attr_reader :habitation

    # ATENÇÃO — fonte recorrente de confusão:
    # Imagens de DWV NÃO são nossas: elas ficam na URL PRÓPRIA do DWV e NÃO
    # baixamos para o nosso Spaces. Por isso aqui usamos a URL crua
    # (picture_url) e NÃO passamos pelo Storage::PublicCdnImageUrl.resolve
    # (o resolver só valida/aceita URLs do nosso CDN/Spaces — e é pra continuar
    # assim). As imagens PRÓPRias do imóvel (ActiveStorage no nosso Spaces) é que
    # passam pelo resolver, em Habitation#image_payload_sources / attached_media.
    # Só entram aqui quando o imóvel é DWV (imovel_dwv == "Sim").
    def raw_dwv_pictures
      return [] unless habitation.dwv_property? && habitation.pictures.is_a?(Array)

      habitation.pictures.each_with_index.filter_map do |picture, index|
        url = picture_url(picture)
        [picture, index, url] if url.present?
      end
    end

    def picture_url(picture)
      return picture.to_s if picture.is_a?(String)
      return unless picture.respond_to?(:[])

      picture["url"].presence ||
        picture[:url].presence ||
        picture["src"].presence ||
        picture[:src].presence ||
        picture["link"].presence ||
        picture[:link].presence
    end

    def covered_by_attached_media?(picture_url)
      return false if attached_media_photos.blank?

      source_path = source_path_from_url(picture_url)
      source_filename = File.basename(source_path.to_s)
      attached_media_photos.any? do |attachment|
        metadata = attachment.blob&.metadata.to_h
        sources = [metadata["source_url"], attachment.filename.to_s]
        sources.any? do |source|
          candidate_path = source_path_from_url(source)
          source.to_s == picture_url.to_s ||
            candidate_path == source_path ||
            File.basename(candidate_path.to_s) == source_filename
        end
      end
    end

    def source_path_from_url(url)
      URI.parse(url.to_s).path.to_s.delete_prefix("/")
    rescue URI::InvalidURIError
      nil
    end

  end
end
