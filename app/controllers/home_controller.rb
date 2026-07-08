class HomeController < ApplicationController
  def index
    # Load active home sections
    @home_sections = Rails.cache.fetch("home_sections_active_v3", expires_in: 1.hour) do
      HomeSection.active.to_a
    end
    @sections_map = @home_sections.index_by(&:section_type)
    
    # Carrossel de Destaques - 12 imóveis (only if section is active)
    if (section = @sections_map["featured_properties"])&.active?
      @featured_properties = cached_home_properties(section, "featured_properties") do
        section
          .apply_property_filters(public_habitations.active.featured)
          .newest_first
          .limit(12)
          .pluck(:id)
      end
    end
    
    # Carrossel de Oportunidades - 12 imóveis com desconto (only if section is active)
    if (section = @sections_map["opportunities"])&.active?
      @opportunity_properties = cached_home_properties(section, "opportunities") do
        section
          .apply_property_filters(
            public_habitations.active
              .where("valor_venda_anterior_cents > valor_venda_cents AND valor_venda_cents > 0")
          )
          .newest_first
          .limit(12)
          .pluck(:id)
      end
    end
    
    # Carrossel de Empreendimentos (only if section is active)
    if (section = @sections_map["developments"])&.active?
      development_payload = cached_home_development_payload(section)
      @recent_properties = load_home_properties(development_payload[:ids])
      @dev_unit_counts = development_payload[:unit_counts]
      @dev_unit_metrics = development_payload[:unit_metrics]
    end
    
    # Imóveis para Locação (only if section is active)
    if (section = @sections_map["rentals"])&.active?
      @rental_properties = cached_home_properties(section, "rentals") do
        section
          .apply_property_filters(public_habitations.active.for_rent)
          .newest_first
          .limit(6)
          .pluck(:id)
      end
      @corporate_properties = cached_home_properties(section, "corporate_properties") do
        public_habitations
          .active
          .home_corporate
          .limit(3)
          .pluck(:id)
      end
    end
    
    # Tipos de imóveis disponíveis (para o formulário de busca) - CACHED
    @property_types = Rails.cache.fetch(Habitation.public_filter_property_types_cache_key(public_tenant.id), expires_in: 12.hours) do
      public_habitations.public_property_types
    end

    # Localizações disponíveis (cidade e bairro/cidade) para multiseleção na home
    @location_options = Rails.cache.fetch(Habitation.public_filter_location_options_cache_key(public_tenant.id), expires_in: 6.hours) do
      public_habitations.public_location_options
    end
    
    # Home settings
    @home_setting ||= HomeSetting.instance
    @hero_images = build_hero_images(@home_setting)
    @hero_preload_source = @hero_images.first&.fetch(:source, nil)
    @hero_preload_mobile_source = @hero_images.first&.fetch(:mobile_source, nil)
    
    # SEO
    @page_name = 'home'
    @page_title = 'Salute Imóveis | Encontre seu Imóvel Ideal'
    @page_description = 'Os melhores imóveis para venda e locação. Apartamentos, casas, terrenos e mais.'
    
    # Cache da página (Browser)
    expires_in 15.minutes, public: true
  end
  
  def sobre
    @page_name = 'sobre'
    @page_title = 'Sobre Nós | Salute Imóveis'
    @page_description = 'Conheça a Salute Imóveis, sua imobiliária de confiança.'
  end
  
  def contato
    @page_name = 'contato'
    @page_title = 'Contato | Salute Imóveis'
    @page_description = 'Entre em contato com a Salute Imóveis. Estamos prontos para ajudar você.'
  end

  private

  def cached_home_properties(section, cache_name)
    ids = Rails.cache.fetch(home_section_cache_key(section, cache_name), expires_in: 15.minutes) do
      Array(yield)
    end

    load_home_properties(ids)
  end

  def cached_home_development_payload(section)
    Rails.cache.fetch(home_section_cache_key(section, "developments"), expires_in: 15.minutes) do
      rows = section
        .apply_property_filters(
          public_habitations
            .empreendimentos_publicos
            .where.not(codigo: nil)
        )
        .newest_first
        .limit(20)
        .pluck(:id, :codigo)

      seen_codes = Set.new
      selected_rows = rows.filter_map do |id, codigo|
        next if codigo.blank? || seen_codes.include?(codigo)

        seen_codes.add(codigo)
        [id, codigo]
      end.first(12)

      dev_codes = selected_rows.map(&:second)

      {
        ids: selected_rows.map(&:first),
        unit_counts: development_unit_counts_for(dev_codes),
        unit_metrics: development_unit_metrics_for(dev_codes)
      }
    end
  end

  def home_section_cache_key(section, cache_name)
    [
      "public_home",
      "tenant",
      public_tenant.id,
      cache_name,
      section.id,
      section.updated_at.to_i
    ].join("/")
  end

  def load_home_properties(ids)
    ids = Array(ids).compact
    return [] if ids.empty?

    records_by_id = public_property_card_scope(public_habitations.where(id: ids)).index_by(&:id)
    ids.filter_map { |id| records_by_id[id] }
  end

  def public_property_card_scope(scope)
    scope
      .with_attached_photos
      .includes(
        :address,
        { constructor: { logo_attachment: :blob } },
        { empreendimento: { constructor: { logo_attachment: :blob } } }
      )
  end

  def development_unit_counts_for(development_codes)
    return {} if development_codes.blank?

    public_habitations
      .where.not(codigo_empreendimento: nil)
      .where(codigo_empreendimento: development_codes)
      .group(:codigo_empreendimento)
      .count
  end

  def development_unit_metrics_for(development_codes)
    return {} if development_codes.blank?

    grouped_values = Hash.new { |hash, key| hash[key] = { areas: [], suites: [], dorms: [], vagas: [] } }

    public_habitations
      .publicly_listable
      .with_public_listing_price
      .where(codigo_empreendimento: development_codes)
      .pluck(:codigo_empreendimento, :area_privativa_m2, :suites_qtd, :dormitorios_qtd, :vagas_qtd)
      .each do |codigo, area, suites, dorms, vagas|
        grouped_values[codigo][:areas] << area if area.to_f.positive?
        grouped_values[codigo][:suites] << suites if suites.to_i.positive?
        grouped_values[codigo][:dorms] << dorms if dorms.to_i.positive?
        grouped_values[codigo][:vagas] << vagas if vagas.to_i.positive?
      end

    grouped_values.transform_values do |values|
      {
        area_label: area_range_label(values[:areas]),
        suites_label: integer_range_label(values[:suites]),
        dorms_label: integer_range_label(values[:dorms]),
        vagas_label: integer_range_label(values[:vagas])
      }
    end
  end

  def integer_range_label(values)
    normalized = values.map(&:to_i).select(&:positive?).uniq.sort
    return if normalized.empty?

    normalized.size == 1 ? normalized.first.to_s : "#{normalized.min} a #{normalized.max}"
  end

  def area_range_label(values)
    normalized = values.map(&:to_i).select(&:positive?)
    return if normalized.empty?

    min = normalized.min
    max = normalized.max
    min == max ? "#{min} m²" : "#{min} a #{max} m²"
  end

  def build_hero_images(home_setting)
    images = home_setting.active_hero_slides.with_attached_image.filter_map do |slide|
      next unless slide.image.attached?

      {
        source: slide.image,
        mobile_source: slide.image,
        alt: slide.alt_text.presence || "Salute Imóveis - Luxo e Exclusividade"
      }
    end

    if images.empty? && home_setting.hero_background_desktop.attached?
      images << {
        source: home_setting.hero_background_desktop,
        mobile_source: (home_setting.hero_background_mobile.attached? ? home_setting.hero_background_mobile : home_setting.hero_background_desktop),
        alt: "Salute Imóveis - Luxo e Exclusividade"
      }
    end

    fallback = helpers.asset_path("hero_05.jpeg")
    images.presence || [{ source: fallback, mobile_source: fallback, alt: "Salute Imóveis - Luxo e Exclusividade" }]
  end
end
