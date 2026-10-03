# Dados compartilhados pelos layouts do hero (Barra e Cartão): fundo, opções dos campos e contagem.
module HomeHeroHelper
  HERO_QUICK_FILTERS = [
    ["frente_mar", "Frente mar"], ["quadra_mar", "Quadra mar"], ["vista_mar", "Vista mar"],
    ["mobiliado", "Mobiliado"], ["pronto", "Pronto morar"], ["na_planta", "Na planta"]
  ].freeze

  # Preload e todos os layouts usam as mesmas URLs e breakpoints.
  def hero_image_sources
    @hero_image_sources ||= begin
      image = Array(@hero_images).first || {}
      source = image[:source]
      mobile = image[:mobile_source] || source
      urls = Storage::PublicImageVariants::HERO.map do |options|
        selected = options[:resize_to_limit].first <= 900 ? mobile : source
        public_image_url(selected, **options).presence || public_image_url(selected).presence || selected
      end
      {
        mobile: urls[0], desktop: urls[3],
        mobile_srcset: "#{urls[0]} 640w, #{urls[1]} 900w",
        desktop_srcset: "#{urls[2]} 1440w, #{urls[3]} 1920w"
      }
    end
  end

  def hero_background_locals
    sources = hero_image_sources
    {
      background_url: sources[:desktop],
      background_srcset: sources[:desktop_srcset],
      background_mobile_srcset: sources[:mobile_srcset],
      background_sizes: "100vw", background_alt: ""
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
