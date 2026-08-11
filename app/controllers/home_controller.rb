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
    expires_in 15.minutes, public: true
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

  def cached_home_properties(section, cache_name)
    ids = Rails.cache.fetch(home_section_cache_key(section, cache_name), expires_in: 15.minutes) do
      Array(yield)
    end

    load_home_properties(ids)
  end

  def cached_home_development_payload(section)
    Rails.cache.fetch(home_section_cache_key(section, "developments"), expires_in: 15.minutes) do
      development_scope = public_habitations
        .empreendimentos_publicos
        .where.not(codigo: nil)

      manual_ids = ordered_section_property_ids(section, development_scope, limit: 12)
      manual_rows = development_scope.where(id: manual_ids).pluck(:id, :codigo)
      manual_rows = manual_ids.filter_map do |manual_id|
        manual_rows.detect { |id, _codigo| id == manual_id }
      end

      automatic_rows = section
        .apply_property_filters(development_scope)
        .where.not(id: manual_ids)
        .newest_first
        .limit(20)
        .pluck(:id, :codigo)

      rows = manual_rows + automatic_rows

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

  def build_home_section_payloads(sections)
    sections.each_with_object({}) do |section, payloads|
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

  def property_payload_for(section)
    properties = cached_home_properties(section, "properties") do
      prioritized_home_property_ids(
        section,
        home_property_auto_scope,
        limit: home_property_limit(section),
        manual_scope: home_property_manual_scope(section)
      )
    end

    payload = home_property_cta(section).merge(kind: "properties", records: properties)
    payload[:corporate_records] = cached_home_properties(section, "corporate_properties") do
      public_habitations.active.home_corporate.limit(3).pluck(:id)
    end if section.corporate_showcase?
    payload
  end

  def home_property_auto_scope
    public_habitations.active.without_developments
  end

  def home_property_manual_scope(section)
    scope = public_habitations.active.without_developments
    scope = scope.for_rent if section.property_filter_enabled?("locacao") || section.section_type == "rentals"
    scope = scope.for_sale if section.property_filter_enabled?("venda")
    scope
  end

  def home_property_limit(section)
    section.property_filter_enabled?("locacao") || section.section_type == "rentals" ? 6 : 12
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

  def prioritized_home_property_ids(section, fallback_scope, limit:, manual_scope: public_habitations.active)
    manual_ids = ordered_section_property_ids(section, manual_scope, limit:)
    remaining = limit - manual_ids.size
    return manual_ids if remaining <= 0

    automatic_scope = section.apply_property_filters(fallback_scope)
    automatic_scope = automatic_scope.newest_first if automatic_scope.respond_to?(:newest_first)

    manual_ids + automatic_scope.where.not(id: manual_ids).limit(remaining).pluck(:id)
  end

  def ordered_section_property_ids(section, scope, limit:)
    requested_ids = section.selected_property_ids
    return [] if requested_ids.empty?

    available_ids = scope.where(id: requested_ids).reorder(nil).pluck(:id).map(&:to_i)
    (requested_ids & available_ids).first(limit)
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
