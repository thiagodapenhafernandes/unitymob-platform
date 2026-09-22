module HomeVideosHelper
  DIRECT_VIDEO_EXTENSIONS = %w[.mp4 .mov .m4v .webm .ogg .ogv .3gp].freeze

  def home_property_video_payload(property)
    Array(property&.videos).filter_map { |item| home_video_payload(item) }.first
  end

  def home_section_item_video_payload(item)
    url = item.source_type == "upload" && item.video_file.attached? ? url_for(item.video_file) : item.source_url
    payload = home_video_payload(url)
    return if payload.blank?

    if item.source_type == "upload" && item.video_file.attached?
      payload[:content_type] = item.video_file.blob.content_type if payload[:direct_url].present?
    end
    payload
  end

  def home_property_video_poster(property, video_payload)
    source = property&.primary_image_source
    poster = public_image_url(source, resize_to_fill: [560, 900], format: :webp, force_variant: true, representation_proxy: true) if source.present?
    poster.presence || video_payload[:poster_url].presence || property&.primary_image_url
  end

  def home_video_price_label(property)
    sale = property&.valor_venda_cents.to_i
    rent = property&.valor_locacao_cents.to_i
    cents = sale.positive? ? sale : rent
    return "Preço sob consulta" unless cents.positive?

    suffix = sale.positive? ? "" : "/mês"
    "#{number_to_currency(cents / 100.0, unit: "R$ ", separator: ",", delimiter: ".", precision: 0)}#{suffix}"
  end

  def home_video_payload(item)
    url = home_video_url(item)
    return if url.blank?

    if (youtube_id = home_youtube_id(url))
      {
        provider: "youtube",
        url:,
        embed_url: "https://www.youtube.com/embed/#{youtube_id}?autoplay=1&rel=0&modestbranding=1&playsinline=1",
        poster_url: "https://img.youtube.com/vi/#{youtube_id}/hqdefault.jpg"
      }
    elsif (vimeo_id = home_vimeo_id(url))
      {
        provider: "vimeo",
        url:,
        embed_url: "https://player.vimeo.com/video/#{vimeo_id}?autoplay=1"
      }
    elsif (instagram_embed_url = home_instagram_embed_url(url))
      {
        provider: "instagram",
        url:,
        embed_url: instagram_embed_url
      }
    else
      {
        provider: "direct",
        url:,
        direct_url: url,
        content_type: home_video_content_type(url)
      } if home_video_content_type(url).present?
    end
  end

  def home_video_url(item)
    raw = if item.is_a?(Hash)
            item["url"] || item[:url] || item["source_url"] || item[:source_url] || item["src"] || item[:src]
          else
            item
          end

    url = raw.to_s.strip
    return if url.blank?
    return "https://www.youtube.com/watch?v=#{home_youtube_id(url)}" if home_youtube_id(url)
    return url if url.start_with?("/")

    uri = URI.parse(url)
    return unless uri.scheme.in?(%w[http https])

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def home_youtube_id(url)
    return url if url.to_s.match?(/\A[A-Za-z0-9_-]{11}\z/)

    uri = URI.parse(url)
    host = uri.host.to_s.downcase
    return uri.path.delete_prefix("/").split("/").first if host == "youtu.be"
    return unless host.match?(/(^|\.)youtube\.com\z/)

    if uri.path.start_with?("/shorts/", "/embed/")
      uri.path.split("/").third
    else
      Rack::Utils.parse_nested_query(uri.query)["v"]
    end
  rescue URI::InvalidURIError
    nil
  end

  def home_vimeo_id(url)
    uri = URI.parse(url)
    host = uri.host.to_s.downcase
    return unless host.match?(/(^|\.)vimeo\.com\z/)

    uri.path.split("/").reverse.find { |part| part.match?(/\A\d+\z/) }
  rescue URI::InvalidURIError
    nil
  end

  def home_instagram_embed_url(url)
    uri = URI.parse(url)
    host = uri.host.to_s.downcase
    return unless host.match?(/(^|\.)instagram\.com\z/)

    parts = uri.path.split("/").compact_blank
    type = parts.first
    code = parts.second
    return unless type.in?(%w[p reel tv]) && code.present?

    "https://www.instagram.com/#{type}/#{code}/embed"
  rescue URI::InvalidURIError
    nil
  end

  def home_video_content_type(url)
    extension = File.extname(URI.parse(url).path.to_s).downcase
    return "video/quicktime" if extension == ".mov"
    return "video/webm" if extension == ".webm"
    return "video/ogg" if extension.in?(%w[.ogg .ogv])
    return "video/3gpp" if extension == ".3gp"

    DIRECT_VIDEO_EXTENSIONS.include?(extension) ? "video/mp4" : nil
  rescue URI::InvalidURIError
    nil
  end
end
