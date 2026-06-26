class HomeSection < ApplicationRecord
  SECTION_TYPE_LABELS = {
    "services" => "Serviços",
    "why_choose_us" => "Por que escolher a Salute",
    "cta_contact" => "Chamada para contato",
    "featured_properties" => "Imóveis em Destaque",
    "opportunities" => "Oportunidades",
    "developments" => "Empreendimentos",
    "rentals" => "Imóveis para Locação"
  }.freeze

  PROPERTY_FILTER_OPTIONS = {
    "destaque_web" => { label: "Destaque Web", column: :destaque_web_flag },
    "super_destaque" => { label: "Super Destaque", column: :festival_salute_flag },
    "lancamento" => { label: "Lançamento", column: :lancamento_flag },
    "tem_placa" => { label: "Tem Placa", column: :tem_placa_flag },
    "exclusivo" => { label: "Exclusivo", column: :exclusivo_flag },
    "imovel_dwv" => {
      label: "Imóvel DWV",
      where: ["LOWER(TRIM(COALESCE(habitations.imovel_dwv, ''))) = ?", "sim"]
    },
    "exibir_no_site" => { label: "Exibir no site", column: :exibir_no_site_flag },
    "administracao_locacao_salute" => { label: "Administração de locação feita pela Salute", column: :salute_rental_management_flag },
    "vitrine_corporate" => { label: "Vitrine Corporate da Página Inicial", column: :home_corporate_flag }
  }.freeze
  LEGACY_PROPERTY_FILTER_KEYS = {
    "exibir_site_salute" => "exibir_no_site"
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
    enabled_property_filters.map { |key| PROPERTY_FILTER_OPTIONS.dig(key, :label) }
  end

  def apply_property_filters(scope)
    enabled_property_filters.reduce(scope) do |filtered_scope, key|
      option = PROPERTY_FILTER_OPTIONS[key]
      if option[:column]
        filtered_scope.where(option[:column] => true)
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
    self.property_filters = PROPERTY_FILTER_OPTIONS.keys.each_with_object({}) do |key, filters|
      legacy_keys = LEGACY_PROPERTY_FILTER_KEYS.select { |_legacy_key, canonical_key| canonical_key == key }.keys
      raw_value = raw_filters[key] || raw_filters[key.to_sym] || legacy_keys.lazy.map { |legacy_key| raw_filters[legacy_key] || raw_filters[legacy_key.to_sym] }.find(&:present?)
      enabled = ActiveModel::Type::Boolean.new.cast(raw_value)
      filters[key] = "1" if enabled
    end
  end

  def clear_home_cache
    Rails.cache.delete("home_sections_active_v3")
    Rails.cache.delete("home_sections_active_v2")
    Rails.cache.delete_matched("views/*") if Rails.cache.respond_to?(:delete_matched)
  rescue NotImplementedError
    Rails.cache.clear
  end
end
