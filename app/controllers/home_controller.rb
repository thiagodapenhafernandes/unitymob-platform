class HomeController < ApplicationController
  def index
    @public_identity = public_identity

    # Load active home sections
    @home_sections = Rails.cache.fetch("home_sections_active_v3:tenant:#{public_tenant.id}", expires_in: 1.hour) do
      public_tenant.home_sections.active.to_a
    end
    @home_section_payloads = build_home_section_payloads(@home_sections)
    
    # Tipos de imóveis disponíveis (para o formulário de busca) - CACHED
    @property_types = Rails.cache.fetch(Habitation.public_filter_property_types_cache_key(public_tenant.id), expires_in: 12.hours) do
      public_habitations.public_property_types
    end

    # Localizações disponíveis (cidade e bairro/cidade) para multiseleção na home
    @location_options = Rails.cache.fetch(Habitation.public_filter_location_options_cache_key(public_tenant.id), expires_in: 6.hours) do
      public_habitations.public_location_options
    end
    
    # Home settings
    @home_setting ||= HomeSetting.instance(tenant: public_tenant)
    @hero_images = build_hero_images(@home_setting)
    @hero_preload_source = @hero_images.first&.fetch(:source, nil)
    @hero_preload_mobile_source = @hero_images.first&.fetch(:mobile_source, nil)
    @announce_property_form = public_tenant.public_forms.active.find_by(slug: PublicForm::DEFAULT_ANNOUNCE_SLUG) if PublicForm.table_exists?
    
    # SEO
    @page_name = 'home'
    @page_title = "#{public_identity.name} | Encontre seu Imóvel Ideal"
    @page_description = 'Os melhores imóveis para venda e locação. Apartamentos, casas, terrenos e mais.'
    
    # Cache da página (Browser)
    if @home_sections.any?(&:blog?)
      # Revalidate HTML so scheduled or withdrawn articles never wait for a browser/CDN TTL.
      expires_now
    else
      expires_in 15.minutes, public: true
    end
  end
  
  # Slides 2..N do hero servidos após o primeiro byte (turbo-frame lazy).
  # O 1º slide (LCP) continua inline no _hero.
  def hero_slides
    home_setting = HomeSetting.instance(tenant: public_tenant)
    @hero_slide_images = build_hero_images(home_setting).drop(1)
    render layout: false
  end

  # Mídia pesada da home (carrossel/vídeo) servida após o primeiro byte
  # (turbo-frame lazy). Shell, títulos e CTAs continuam server-side no
  # index. Escopo por tenant; exclude replica a deduplicação entre seções.
  def home_section
    section = public_tenant.home_sections.active.find(params[:id])
    @home_shown_property_ids = params[:exclude].to_s.split(",").map(&:to_i)
    payload = build_home_section_payloads([section])[section.id] || {}
    bg_class = params[:i].to_i.odd? ? 'public-theme-home-section public-theme-home-section--alt' : 'public-theme-home-section'
    render "home_section_frame", layout: false,
      locals: { section:, payload:, part: params[:part].to_s, bg_class: }
  end

  def sobre
    load_public_identity
    @page_name = 'sobre'
    @page_title = "Sobre Nós | #{@public_identity.name}"
    @page_description = "Conheça a #{@public_identity.name}, sua imobiliária de confiança."
  end
  
  def contato
    load_public_identity
    @page_name = 'contato'
    @page_title = "Contato | #{@public_identity.name}"
    @page_description = "Entre em contato com a #{@public_identity.name}. Estamos prontos para ajudar você."
  end

  private

  def public_identity
    @public_identity ||= Tenants::PublicIdentity.new(public_tenant)
  end

  def load_public_identity
    @public_identity = public_identity
    @contact_setting = ContactSetting.instance(tenant: public_tenant)
    @footer_setting = FooterSetting.instance(tenant: public_tenant)
    @public_site_profile = PublicSiteProfile.current(tenant: public_tenant)
    @business_hours = @contact_setting.business_hours.presence
  end

  def cached_home_properties(section, cache_name, variant: nil)
    ids = Rails.cache.fetch([home_section_cache_key(section, cache_name), variant].compact.join("/"), expires_in: 15.minutes) do
      Array(yield)
    end

    load_home_properties(ids)
  end

  def cached_home_development_payload(section)
    Rails.cache.fetch(home_section_cache_key(section, "developments"), expires_in: 15.minutes) do
      selected_rows = HomeSections::Showcase.new(section, habitations: public_habitations).development_rows

      dev_codes = selected_rows.map(&:second)

      {
        ids: selected_rows.map(&:first),
        unit_counts: (dev_metrics = PublicSite::DevelopmentUnitMetrics.new(public_habitations, dev_codes)).unit_counts,
        unit_metrics: dev_metrics.unit_metrics
      }
    end
  end

  def cached_home_city_groups(section)
    Rails.cache.fetch(home_section_cache_key(section, "city_links"), expires_in: 6.hours) do
      HomeSections::Showcase.new(section, habitations: public_habitations).city_groups
    end
  end

  def build_home_section_payloads(sections)
    sections.each_with_object({}) do |section, payloads|
      if section.blog?
        @home_blog_articles ||= public_tenant.blog_articles.publicly_visible.recent.with_attached_cover.includes(:blog_categories).limit(3).to_a
        payloads[section.id] = { kind: "blog", records: @home_blog_articles }
        next
      end
      if section.city_links?
        payloads[section.id] = { kind: "city_links", records: cached_home_city_groups(section) }
        next
      end
      next unless section.property_content_section?

      payloads[section.id] =
        if section.development_content?
          development_payload_for(section)
        else
          property_payload_for(section)
        end
    end
  end

  def development_payload_for(section)
    development_payload = cached_home_development_payload(section)
    {
      kind: "developments",
      records: load_home_properties(development_payload[:ids]),
      unit_counts: development_payload[:unit_counts],
      unit_metrics: development_payload[:unit_metrics],
      cta_label: "Ver Todos os Empreendimentos",
      cta_path: empreendimentos_path
    }
  end

  # Seções de imóveis em sequência não repetem o mesmo imóvel: cada uma pula
  # os já exibidos acima. Vídeos ficam de fora (outro formato de vitrine).
  def property_payload_for(section)
    videos = section.featured_videos?
    shown = videos ? [] : home_shown_property_ids
    showcase = HomeSections::Showcase.new(section, habitations: public_habitations, exclude_ids: shown)
    exclusion_key = Digest::SHA1.hexdigest(shown.sort.join(","))[0, 12] if shown.any?
    properties = cached_home_properties(section, "properties", variant: exclusion_key) { showcase.property_ids }
    shown.concat(properties.map(&:id)) unless videos

    kind = videos ? "property_videos" : "properties"
    payload = home_property_cta(section).merge(kind:, records: properties)
    payload[:corporate_records] = cached_home_properties(section, "corporate_properties") do
      public_habitations.active.home_corporate.limit(3).pluck(:id)
    end if section.corporate_showcase? && section.selected_property_ids.empty?
    payload
  end

  def home_shown_property_ids
    @home_shown_property_ids ||= []
  end

  def home_property_cta(section)
    { cta_label: section.public_property_cta_label, cta_path: habitations_path(section.public_property_filter_params) }
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

    records = public_property_card_scope(public_habitations.where(id: ids)).to_a
    PublicSite::CardPhotoPreloader.new(records, limit: 3).call
    records_by_id = records.index_by(&:id)
    ids.filter_map { |id| records_by_id[id] }
  end

  def public_property_card_scope(scope)
    scope
      .includes(
        :address,
        { constructor: { logo_attachment: :blob } },
        { empreendimento: { constructor: { logo_attachment: :blob } } }
      )
  end

  def build_hero_images(home_setting)
    images = home_setting.active_hero_slides.with_attached_image.filter_map do |slide|
      next unless slide.image.attached?

      {
        source: slide.image,
        mobile_source: slide.image,
        alt: slide.alt_text.presence || "#{public_identity.name} - imóveis em destaque"
      }
    end

    if images.empty? && home_setting.hero_background_desktop.attached?
      images << {
        source: home_setting.hero_background_desktop,
        mobile_source: (home_setting.hero_background_mobile.attached? ? home_setting.hero_background_mobile : home_setting.hero_background_desktop),
        alt: "#{public_identity.name} - imóveis em destaque"
      }
    end

    if images.empty?
      fallback_source = public_habitation_hero_source
      images << { source: fallback_source, mobile_source: fallback_source, alt: "#{public_identity.name} - imóvel em destaque" } if fallback_source.present?
    end

    images
  end

  def public_habitation_hero_source
    public_property_card_scope(
      public_habitations
        .active
        .with_public_listing_price
        .newest_first
        .limit(20)
    ).detect { |habitation| habitation.public_image_sources.any? }&.public_image_sources&.first
  end
end
