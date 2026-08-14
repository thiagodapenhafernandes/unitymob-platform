class HomeSection < ApplicationRecord
  include TenantScoped
  SECTION_TYPE_LABELS = {
    "services" => "Serviços",
    "why_choose_us" => "Por que escolher a imobiliária",
    "cta_contact" => "Chamada para contato",
    "featured_properties" => "Imóveis em Destaque",
    "opportunities" => "Oportunidades",
    "developments" => "Empreendimentos",
    "rentals" => "Imóveis para Locação"
  }.freeze

  PROPERTY_FILTER_OPTIONS = {
    "venda" => { label: "Venda", scope: :for_sale },
    "locacao" => { label: "Locação", scope: :for_rent },
    "empreendimentos" => { label: "Empreendimentos", scope: :empreendimentos_publicos },
    "destaque_web" => { label: "Destaque Web", column: :destaque_web_flag },
    "super_destaque" => { label: "Super Destaque", column: :festival_flag },
    "lancamento" => { label: "Lançamento", column: :lancamento_flag },
    "frente_mar" => { label: "Frente Mar", scope: :frente_mar },
    "quadra_mar" => { label: "Quadra Mar", scope: :quadra_mar },
    "vista_mar" => { label: "Vista Mar", scope: :vista_mar },
    "preco_reduzido" => { label: "Preço reduzido", scope: :opportunity },
    "garden" => { label: "Garden", scope: :garden },
    "pronto" => { label: "Pronto para morar", scope: :pronto },
    "na_planta" => { label: "Na planta", scope: :na_planta },
    "em_construcao" => { label: "Em construção", scope: :em_construcao },
    "sol_manha" => { label: "Sol da manhã", scope: :sol_manha },
    "sol_tarde" => { label: "Sol da tarde", scope: :sol_tarde },
    "mobiliado" => { label: "Mobiliado", scope: :mobiliado },
    "decorado" => { label: "Decorado", scope: :decorado },
    "aceita_permuta" => { label: "Aceita permuta", scope: :aceita_permuta },
    "aceita_financiamento" => { label: "Aceita financiamento", scope: :aceita_financiamento },
    "com_tour_virtual" => {
      label: "Com tour virtual",
      where: ["NULLIF(BTRIM(COALESCE(habitations.tour_virtual, '')), '') IS NOT NULL"]
    },
    "com_video" => {
      label: "Com vídeo",
      where: ["jsonb_typeof(habitations.videos) = 'array' AND jsonb_array_length(habitations.videos) > 0"]
    },
    "com_fotos" => { label: "Com fotos", scope: :with_photos },
    "tem_placa" => { label: "Tem Placa", column: :tem_placa_flag },
    "exclusivo" => { label: "Exclusivo", column: :exclusivo_flag },
    "imovel_dwv" => {
      label: "Imóvel DWV",
      where: ["LOWER(TRIM(COALESCE(habitations.imovel_dwv, ''))) = ?", "sim"]
    },
    "exibir_no_site" => { label: "Exibir no site", column: :exibir_no_site_flag },
    "administracao_locacao" => { label: "Administração de locação", column: :rental_management_flag },
    "vitrine_corporate" => { label: "Vitrine Corporate da Página Inicial", column: :home_corporate_flag }
  }.freeze
  LEGACY_PROPERTY_FILTER_KEYS = {
    "exibir_site_portal" => "exibir_no_site"
  }.freeze
  PROPERTY_FILTER_ARRAY_KEYS = %w[selected_property_ids].freeze
  PROPERTY_FILTER_PARAM_KEYS = (PROPERTY_FILTER_OPTIONS.keys + PROPERTY_FILTER_ARRAY_KEYS).freeze
  PROPERTY_SECTION_TYPES = %w[featured_properties opportunities developments rentals].freeze
  PUBLIC_CHARACTERISTIC_FILTERS = {
    "destaque_web" => "featured",
    "super_destaque" => "festival_flag",
    "lancamento" => "lancamento",
    "frente_mar" => "frente_mar",
    "quadra_mar" => "quadra_mar",
    "vista_mar" => "vista_mar",
    "preco_reduzido" => "opportunity",
    "garden" => "garden",
    "pronto" => "pronto",
    "na_planta" => "na_planta",
    "em_construcao" => "em_construcao",
    "sol_manha" => "sol_manha",
    "sol_tarde" => "sol_tarde",
    "mobiliado" => "mobiliado",
    "decorado" => "decorado"
  }.freeze
  PUBLIC_BOOLEAN_FILTER_PARAMS = {
    "aceita_permuta" => :accepts_exchange,
    "aceita_financiamento" => :accepts_financing
  }.freeze
  PUBLIC_CTA_SUFFIX_FILTERS = %w[
    frente_mar quadra_mar vista_mar garden pronto na_planta em_construcao sol_manha sol_tarde
    mobiliado decorado lancamento
  ].freeze
  LEGACY_SECTION_TYPE_FILTERS = {
    "featured_properties" => %w[destaque_web],
    "opportunities" => %w[preco_reduzido],
    "developments" => %w[empreendimentos],
    "rentals" => %w[locacao]
  }.freeze

  # Associations
  has_many :home_section_items, dependent: :destroy
  
  # Enum
  enum section_type: {
    services: 0,
    why_choose_us: 1,
    cta_contact: 2,
    featured_properties: 3,
    opportunities: 4,
    developments: 5,
    rentals: 6
  }
  
  # Validations
  validates :section_type, :title, presence: true

  before_validation :normalize_property_filters
  after_commit :clear_home_cache
  
  # Scopes
  scope :active, -> { where(active: true).order(:order_position, :id) }
  scope :ordered, -> { order(:order_position, :id) }

  def self.section_type_options
    section_types.keys.map { |key| [SECTION_TYPE_LABELS.fetch(key, key.humanize), key] }
  end

  def self.infer_section_type_from_filters(filters, fallback: nil)
    normalized_filters = filters || {}
    enabled = ->(key) { ActiveModel::Type::Boolean.new.cast(normalized_filters[key.to_s] || normalized_filters[key.to_sym]) }

    return "developments" if enabled.call("empreendimentos")
    return "rentals" if enabled.call("locacao")
    return "opportunities" if enabled.call("preco_reduzido")

    fallback.presence_in(section_types.keys) || "featured_properties"
  end

  def section_type_label
    SECTION_TYPE_LABELS.fetch(section_type, section_type.to_s.humanize)
  end

  def enabled_property_filters
    PROPERTY_FILTER_OPTIONS.keys.select { |key| property_filter_enabled?(key) }
  end

  def property_filter_enabled?(key)
    raw_filters = property_filters || {}
    values = [raw_filters[key.to_s]]
    values.concat(LEGACY_PROPERTY_FILTER_KEYS.select { |_legacy_key, canonical_key| canonical_key == key.to_s }.keys.map { |legacy_key| raw_filters[legacy_key] })

    values.any? { |value| ActiveModel::Type::Boolean.new.cast(value) }
  end

  def property_filter_labels
    labels = enabled_property_filters.map { |key| PROPERTY_FILTER_OPTIONS.dig(key, :label) }
    labels << "#{selected_property_ids.size} imóveis selecionados" if selected_property_ids.any?
    labels
  end

  def property_content_section?
    section_type.in?(PROPERTY_SECTION_TYPES) || enabled_property_filters.any? || selected_property_ids.any?
  end

  def development_content?
    property_filter_enabled?("empreendimentos") || section_type == "developments"
  end

  def corporate_showcase?
    property_filter_enabled?("vitrine_corporate") || section_type == "rentals"
  end

  def public_section_kind_label
    return section_type_label unless property_content_section?
    return "Empreendimentos" if development_content?

    "Imóveis"
  end

  def public_property_filter_params
    params = {}
    characteristics = []

    params[:transaction_type] = "aluguel" if property_filter_enabled?("locacao") || section_type == "rentals"
    params[:transaction_type] = "venda" if property_filter_enabled?("venda")

    PUBLIC_CHARACTERISTIC_FILTERS.each do |filter_key, param_value|
      characteristics << param_value if property_filter_enabled?(filter_key)
    end

    PUBLIC_BOOLEAN_FILTER_PARAMS.each do |filter_key, param_key|
      params[param_key] = "1" if property_filter_enabled?(filter_key)
    end

    params[:characteristics] = characteristics if characteristics.any?
    params
  end

  def public_property_cta_label
    base_label = if property_filter_enabled?("locacao") || section_type == "rentals"
                   "Ver Todos os Imóveis para Alugar"
                 else
                   "Ver Todos os Imóveis"
                 end
    suffix_labels = PUBLIC_CTA_SUFFIX_FILTERS.filter_map do |filter_key|
      PROPERTY_FILTER_OPTIONS.dig(filter_key, :label) if property_filter_enabled?(filter_key)
    end

    ([base_label] + suffix_labels).join(" ")
  end

  def legacy_filter_keys
    LEGACY_SECTION_TYPE_FILTERS.fetch(section_type, [])
  end

  def selected_property_ids
    raw_filters = property_filters || {}
    values = raw_filters["selected_property_ids"] || raw_filters[:selected_property_ids]

    normalize_selected_property_ids(values)
  end

  def apply_property_filters(scope)
    enabled_property_filters.reduce(scope) do |filtered_scope, key|
      option = PROPERTY_FILTER_OPTIONS[key]
      if option[:column]
        filtered_scope.where(option[:column] => true)
      elsif option[:scope] && filtered_scope.respond_to?(option[:scope])
        filtered_scope.public_send(option[:scope])
      elsif option[:where]
        filtered_scope.where(*option[:where])
      else
        filtered_scope
      end
    end
  end

  private

  def normalize_property_filters
    raw_filters = property_filters || {}
    normalized_filters = PROPERTY_FILTER_OPTIONS.keys.each_with_object({}) do |key, filters|
      legacy_keys = LEGACY_PROPERTY_FILTER_KEYS.select { |_legacy_key, canonical_key| canonical_key == key }.keys
      raw_value = raw_filters[key] || raw_filters[key.to_sym] || legacy_keys.lazy.map { |legacy_key| raw_filters[legacy_key] || raw_filters[legacy_key.to_sym] }.find(&:present?)
      enabled = ActiveModel::Type::Boolean.new.cast(raw_value)
      filters[key] = "1" if enabled
    end

    selected_ids = normalize_selected_property_ids(raw_filters["selected_property_ids"] || raw_filters[:selected_property_ids])
    normalized_filters["selected_property_ids"] = selected_ids if selected_ids.any?

    self.property_filters = normalized_filters
  end

  def normalize_selected_property_ids(values)
    Array(values)
      .flat_map { |value| value.to_s.split(/[,\s]+/) }
      .filter_map { |value| Integer(value, exception: false) }
      .select(&:positive?)
      .uniq
  end

  def clear_home_cache
    Rails.cache.delete("home_sections_active_v3:tenant:#{tenant_id}")
    Rails.cache.delete("home_sections_active_v2:tenant:#{tenant_id}")
    Rails.cache.delete_matched("public_home/tenant/*") if Rails.cache.respond_to?(:delete_matched)
    Rails.cache.delete_matched("views/*") if Rails.cache.respond_to?(:delete_matched)
  rescue NotImplementedError
    Rails.cache.clear
  end
end
