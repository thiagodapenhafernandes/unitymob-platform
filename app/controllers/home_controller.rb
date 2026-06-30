class HomeController < ApplicationController
  def index
    # Load active home sections
    @home_sections = Rails.cache.fetch("home_sections_active_v3", expires_in: 1.hour) do
      HomeSection.active.to_a
    end
    @sections_map = @home_sections.index_by(&:section_type)
    
    # Carrossel de Destaques - 12 imóveis (only if section is active)
    if (section = @sections_map["featured_properties"])&.active?
      @featured_properties = section
        .apply_property_filters(public_habitations.active.featured.with_attached_photos)
        .newest_first
        .limit(12)
    end
    
    # Carrossel de Oportunidades - 12 imóveis com desconto (only if section is active)
    if (section = @sections_map["opportunities"])&.active?
      @opportunity_properties = section
        .apply_property_filters(
          public_habitations.active
            .with_attached_photos
            .where("valor_venda_anterior_cents > valor_venda_cents AND valor_venda_cents > 0")
        )
        .newest_first
        .limit(12)
    end
    
    # Carrossel de Empreendimentos (only if section is active)
    if (section = @sections_map["developments"])&.active?
      all_developments = section
        .apply_property_filters(
          public_habitations
            .empreendimentos_publicos
            .with_attached_photos
            .where.not(codigo: nil)
        )
        .newest_first
        .limit(20)
      
      # Filtrar duplicados por codigo
      seen_codes = Set.new
      @recent_properties = all_developments.select do |dev|
        next false if seen_codes.include?(dev.codigo)
        seen_codes.add(dev.codigo)
        true
      end.first(12)

      # Pre-calculate unit counts for development carousel to avoid N+1
      dev_codes = @recent_properties.map(&:codigo).compact
      @dev_unit_counts = public_habitations.where.not(codigo_empreendimento: nil)
                                   .where(codigo_empreendimento: dev_codes)
                                   .group(:codigo_empreendimento)
                                   .count
    end
    
    # Imóveis para Locação (only if section is active)
    if (section = @sections_map["rentals"])&.active?
      @rental_properties = section
        .apply_property_filters(public_habitations.active.for_rent.with_attached_photos)
        .newest_first
        .limit(6)
      @corporate_properties = public_habitations.active.home_corporate.with_attached_photos.limit(3)
    end
    
    # Tipos de imóveis disponíveis (para o formulário de busca) - CACHED
    @property_types = Rails.cache.fetch("home_property_types_v6/tenant/#{public_tenant.id}", expires_in: 12.hours) do
      public_habitations.public_property_types
    end

    # Localizações disponíveis (cidade e bairro/cidade) para multiseleção na home
    @location_options = Rails.cache.fetch("home_location_options_v2/tenant/#{public_tenant.id}", expires_in: 6.hours) do
      public_habitations.public_location_options
    end
    
    # Home settings
    @home_setting = HomeSetting.instance
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
