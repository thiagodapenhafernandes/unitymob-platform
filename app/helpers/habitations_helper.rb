module HabitationsHelper
  CATALOG_PROPERTY_IMAGE_PREVIEW_LIMIT = 6

  def catalog_property_image_urls(property, limit: 8)
    attached_sources = property.card_image_sources(CATALOG_PROPERTY_IMAGE_PREVIEW_LIMIT)
    urls = catalog_image_urls_from(attached_sources, limit:)
    return urls if urls.size >= limit

    payload_sources = property.image_payload_sources.first(CATALOG_PROPERTY_IMAGE_PREVIEW_LIMIT)
    if attached_sources.blank? && payload_sources.blank? && property.respond_to?(:use_development_photos?) && property.use_development_photos?
      payload_sources += property.development_image_payload_sources.first(6)
    end

    (urls + catalog_image_urls_from(payload_sources, limit: limit - urls.size)).uniq.first(limit)
  end

  def catalog_property_image_url(source)
    Storage::PublicCdnImageUrl.resolve(source)
  end

  def catalog_property_image_count(property)
    property.public_image_sources.size
  end

  def catalog_property_image_preview_count(property, total_count: nil)
    [total_count || catalog_property_image_count(property), CATALOG_PROPERTY_IMAGE_PREVIEW_LIMIT].min
  end

  def catalog_image_urls_from(sources, limit:)
    Array(sources).flat_map do |source|
      [
        catalog_property_image_url(source),
        *public_image_fallback_urls(source)
      ]
    end.compact_blank.uniq.first(limit)
  end

  def public_gallery_image_class(source)
    dimensions = public_image_dimensions(source)
    orientation =
      if dimensions
        width, height = dimensions
        ratio = width.to_f / height.to_f

        if ratio < 0.85
          "portrait"
        elsif ratio > 1.2
          "landscape"
        else
          "balanced"
        end
      end

    ["public-habitations-show__gallery-image", ("public-habitations-show__gallery-image--#{orientation}" if orientation)].compact.join(" ")
  end

  def public_gallery_image_style(source, primary: false)
    dimensions = public_image_dimensions(source)
    return nil unless dimensions

    width, height = dimensions
    return nil if width.to_i <= 0 || height.to_i <= 0

    height_ratio = height.to_f / width.to_f
    position_y = if primary && height_ratio > 1.15
                   50 + ((height_ratio - 1.0) * 42)
                 else
                   50
                 end
    position_y = position_y.clamp(50, 86)

    css_position_y = format("%.1f", position_y).sub(/\.0\z/, "")
    "--public-gallery-object-position-y: #{css_position_y}%;"
  end

  def public_image_dimensions(source)
    attachment = source.try(:[], "attachment") || source.try(:[], :attachment)
    metadata = attachment&.blob&.metadata

    width = metadata&.fetch("width", nil).to_i
    height = metadata&.fetch("height", nil).to_i
    return [width, height] if width.positive? && height.positive?

    width = source.try(:[], "width") || source.try(:[], :width)
    height = source.try(:[], "height") || source.try(:[], :height)
    width = width.to_i
    height = height.to_i
    return [width, height] if width.positive? && height.positive?

    nil
  end

  def public_property_map_coordinates(property)
    lat = property&.latitude
    lng = property&.longitude
    lat = property&.read_attribute(:latitude) if lat.blank? && property&.has_attribute?(:latitude)
    lng = property&.read_attribute(:longitude) if lng.blank? && property&.has_attribute?(:longitude)

    lat = lat.to_f
    lng = lng.to_f
    return nil unless lat.between?(-90, 90) && lng.between?(-180, 180)
    return nil if lat.zero? && lng.zero?

    [lat, lng]
  end

  def public_property_map_place_label(property)
    [property&.bairro, property&.cidade, property&.uf].compact_blank.join(" - ")
  end

  def public_property_media_url(property)
    candidate = Array(property&.videos).compact_blank.first || property&.tour_virtual.to_s.presence
    uri = URI.parse(candidate.to_s)
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  # Características disponíveis para filtros
  CHARACTERISTICS = {
    'lancamento' => { label: 'Lançamento', icon: 'bi-stars' },
    'na_planta' => { label: 'Na Planta', icon: 'bi-map' },
    'pronto' => { label: 'Pronto Para Morar', icon: 'bi-check-all' },
    'frente_mar' => { label: 'Frente Mar', icon: 'bi-water' },
    'quadra_mar' => { label: 'Quadra Mar', icon: 'bi-building' },
    'vista_mar' => { label: 'Vista Mar', icon: 'bi-eye' },
    'churrasqueira' => { label: 'Churrasqueira', icon: 'bi-fire' },
    'cozinha_gourmet_churrasqueira' => { label: 'Cozinha gourmet com churrasqueira', icon: 'bi-fire' },
    'mobiliado' => { label: 'Mobiliado', icon: 'bi-house-heart' },
    'sacada' => { label: 'Sacada', icon: 'bi-door-open' },
    'decorado' => { label: 'Decorado', icon: 'bi-palette' },
    'closet' => { label: 'Closet', icon: 'bi-box' },
    'semi_mobiliado' => { label: 'Semi Mobiliado', icon: 'bi-house' },
    'lavabo' => { label: 'Lavabo', icon: 'bi-droplet' },
    'lavanderia' => { label: 'Lavanderia', icon: 'bi-basket' },
    'dependencia_empregada' => { label: 'Dependência de empregada', icon: 'bi-door-closed' },
    'hidromassagem' => { label: 'Hidromassagem', icon: 'bi-moisture' },
    'piscina' => { label: 'Piscina', icon: 'bi-water' },
    'sala_estar' => { label: 'Sala de Estar', icon: 'bi-tv' },
    'sala_jantar' => { label: 'Sala de Jantar', icon: 'bi-egg-fried' },
    'sol_manha' => { label: 'Sol da manhã', icon: 'bi-sunrise' },
    'sol_tarde' => { label: 'Sol da tarde', icon: 'bi-sunset' },
    'sol_dia_todo' => { label: 'Sol o dia todo', icon: 'bi-sun' },
    'varanda' => { label: 'Varanda', icon: 'bi-door-open' }
  }.freeze
  
  # Retorna contador de imóveis com determinada característica.
  # Escopado por conta: usa Current.tenant (setado no site público) e inclui o
  # tenant_id na chave de cache para não vazar contagens entre contas. Sem tenant
  # resolvido, mantém o comportamento global anterior explicitamente.
  def characteristic_counter(characteristic)
    scope = Current.tenant&.habitations || Habitation
    Rails.cache.fetch("characteristic_count:t#{Current.tenant&.id || 'public'}:#{characteristic}", expires_in: 1.hour) do
      scope.active.with_photos.send(characteristic).count
    rescue NoMethodError
      0
    end
  end
  
  # Retorna badges de características do imóvel
  def property_badges(property)
    badges = []
    
    # Lançamento
    badges << { text: 'NOVIDADE', class: 'badge-new' } if property.lancamento_flag
    
    # Frente/Vista/Quadra mar
    badges << { text: 'Vista Mar', class: 'badge-ocean' } if property_has_characteristic?(property, 'vista_mar')
    badges << { text: 'Frente Mar', class: 'badge-ocean' } if property_has_characteristic?(property, 'frente_mar')
    badges << { text: 'Quadra Mar', class: 'badge-ocean' } if property_has_characteristic?(property, 'quadra_mar')
    
    # Churrasqueira
    badges << { text: 'Churrasqueira', class: 'badge-feature' } if property_has_characteristic?(property, 'churrasqueira')
    
    # Mobiliado
    badges << { text: 'Mobiliado', class: 'badge-furnished' } if property.mobiliado_flag
    
    # Decorado
    badges << { text: 'Decorado', class: 'badge-feature' } if property_has_characteristic?(property, 'decorado')
    
    badges.take(3) # Limitar a 3 badges
  end
  
  # Verifica se o imóvel tem determinada característica
  def property_has_characteristic?(property, characteristic)
    return false unless property
    
    case characteristic
    when 'frente_mar'
      property.caracteristicas&.dig('frente_mar') == 'true' ||
        check_jsonb_text(property.caracteristicas, 'frente', 'mar')
    when 'quadra_mar'
      property.caracteristicas&.dig('quadra_mar') == 'true' ||
        check_jsonb_text(property.caracteristicas, 'quadra', 'mar')
    when 'vista_mar'
      check_jsonb_text(property.caracteristicas, 'vista', 'mar')
    when 'churrasqueira'
      check_jsonb_text(property.caracteristicas, 'churrasqueira') ||
        check_jsonb_array(property.infra_estrutura, 'churrasqueira')
    when 'cozinha_gourmet_churrasqueira'
      (check_jsonb_text(property.caracteristicas, 'cozinha', 'gourmet') ||
        check_jsonb_text(property.caracteristicas, 'gourmet')) &&
        property_has_characteristic?(property, 'churrasqueira')
    when 'mobiliado'
      property.mobiliado_flag == true
    when 'decorado'
      check_jsonb_text(property.caracteristicas, 'decorado')
    when 'dependencia_empregada'
      check_jsonb_text(property.caracteristicas, 'depend', 'empreg') ||
        check_jsonb_text(property.caracteristicas, 'dep', 'empreg') ||
        check_jsonb_text(property.caracteristicas, 'quarto', 'empreg')
    when 'sol_manha'
      %w[leste nordeste sudeste].include?(I18n.transliterate(property.face.to_s).downcase) ||
        check_jsonb_text(property.caracteristicas, 'sol', 'manha')
    when 'sol_tarde'
      %w[oeste noroeste sudoeste].include?(I18n.transliterate(property.face.to_s).downcase) ||
        check_jsonb_text(property.caracteristicas, 'sol', 'tarde')
    when 'sol_dia_todo'
      I18n.transliterate(property.face.to_s).downcase == 'norte' ||
        check_jsonb_text(property.caracteristicas, 'sol', 'dia', 'todo')
    when 'piscina'
      property.piscina_flag == true ||
        check_jsonb_text(property.caracteristicas, 'piscina') ||
        check_jsonb_array(property.infra_estrutura, 'piscina')
    else
      false
    end
  end
  
  # Opções de ordenação
  def sort_options
    [
      ['Mais Recentes', 'newest'],
      ['Mais Antigos', 'oldest'],
      ['Menor Preço', 'price_asc'],
      ['Maior Preço', 'price_desc'],
      ['Menor Área', 'area_asc'],
      ['Maior Área', 'area_desc']
    ]
  end
  
  # Retorna label de ordenação atual
  def current_sort_label(sort)
    sort_options.find { |opt| opt[1] == sort }&.first || 'Mais Recentes'
  end

  def formatted_habitation_description(content)
    description = content.to_s
      .gsub(/\r\n?/, "\n")
      .gsub(/[ \t]+/, " ")
      .gsub(/([.!?])(?=[^\s<])/, "\\1 ")
      .gsub(/\n{3,}/, "\n\n")
      .strip
    return tag.p("Sem descrição disponível.") if description.blank?

    if description.match?(/<[^>]+>/)
      sanitize(paragraphize_single_block_description(description), tags: %w[p div br strong em b i ul ol li h3 h4 h5 blockquote a], attributes: %w[href target rel class])
    else
      simple_format(description)
    end
  end
  
  # Toggle característica em array de características
  def toggle_characteristic(current_chars, char)
    chars = current_chars.is_a?(Array) ? current_chars : (current_chars.present? ? [current_chars] : [])
    
    if chars.include?(char)
      chars - [char]
    else
      chars + [char]
    end
  end
  
  private

  def paragraphize_single_block_description(html)
    fragment = Nokogiri::HTML::DocumentFragment.parse(html)
    return html if fragment.css("p, br, ul, ol, li, h3, h4, h5, blockquote").any?

    text = fragment.text.squish
    return html if text.length < 700

    paragraphs = description_sentences(text).each_with_object([]) do |sentence, memo|
      if memo.empty? || memo.last.length >= 420 || memo.last.count(".!?") >= 3
        memo << sentence
      else
        memo[-1] = "#{memo.last} #{sentence}"
      end
    end

    return html if paragraphs.size < 2

    paragraphs.map { |paragraph| tag.p(paragraph) }.join
  end

  def description_sentences(text)
    text
      .scan(/[^.!?]+[.!?]+(?:["”’])?|[^.!?]+$/)
      .map(&:strip)
      .reject(&:blank?)
  end
  
  def check_jsonb_text(jsonb, *keywords)
    return false unless jsonb.is_a?(Hash)
    
    text = jsonb.values.join(' ').downcase
    keywords.all? { |keyword| text.include?(keyword.downcase) }
  end
  
  def check_jsonb_array(jsonb, keyword)
    return false unless jsonb.is_a?(Array)
    
    jsonb.any? { |item| item.to_s.downcase.include?(keyword.downcase) }
  end
end
