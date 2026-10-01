# Dados compartilhados pelos layouts do hero (Barra e Cartão): fundo, opções dos campos e contagem.
module HomeHeroHelper
  HERO_QUICK_FILTERS = [
    ["frente_mar", "Frente mar"], ["quadra_mar", "Quadra mar"], ["vista_mar", "Vista mar"],
    ["mobiliado", "Mobiliado"], ["pronto", "Pronto morar"], ["na_planta", "Na planta"]
  ].freeze

  # Locals do componente public_theme/components/hero a partir da primeira imagem do hero (mesma regra do hero luxury).
  def hero_background_locals
    image = Array(@hero_images).first || {}
    source = image[:source]
    mobile_source = image[:mobile_source] || source
    background = public_image_url(source, resize_to_limit: [1920, 1080], format: :webp, force_variant: true, representation_proxy: true).presence || public_image_url(source).presence || source
    mobile = public_image_url(mobile_source, resize_to_limit: [900, 1600], format: :webp, force_variant: true, representation_proxy: true).presence || public_image_url(mobile_source).presence || mobile_source
    {
      background_url: background, background_mobile_srcset: mobile, background_sizes: "100vw", background_alt: ""
    }
  end

  # Cor e opacidade da sobreposição + tamanho do título, configurados na Home (variáveis CSS do componente).
  def hero_layout_style
    setting = @home_setting
    color = setting.overlay_color.presence || "#000000"
    opacity = (setting.overlay_opacity || 0.7).to_f.clamp(0, 1)
    [
      "--hero-overlay-start: #{color}#{format("%02x", (opacity * 255).to_i)}",
      "--hero-overlay-end: #{color}#{format("%02x", ((opacity * 0.45) * 255).to_i)}",
      "--hero-title-configured-size: #{setting.hero_title_font_size_value}px",
      "--hero-subtitle-configured-size: #{setting.hero_subtitle_font_size_value}px"
    ].join("; ")
  end

  def hero_location_options
    Array(@location_options).filter_map do |option|
      label, value = option.is_a?(Hash) ? option.symbolize_keys.values_at(:label, :value) : Array(option).values_at(0, -1)
      [label, value] if value.present?
    end
  end

  def hero_bedroom_options
    [["Dormitórios", ""]] + (1..4).map { |count| ["#{count}+", count.to_s] }
  end

  # "Mais de 3.000 imóveis em Balneário Camboriú e região" (arredonda para baixo; some se a base for pequena).
  def hero_listing_summary
    count = @hero_listing_count.to_i
    return if count < 20

    rounded = count >= 100 ? (count / 100) * 100 : (count / 10) * 10
    city = @public_identity&.primary_city
    safe_join(["Mais de ", tag.strong(number_with_delimiter(rounded, delimiter: ".")), " imóveis", (" em #{city} e região" if city.present?)].compact)
  end
end
