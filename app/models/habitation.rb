# == Schema Information
#
# Table name: habitations
#
class Habitation < ApplicationRecord
  include TenantScoped
  include PhoneNormalizable

  REVIEW_RETURN_WARNING_THRESHOLD = 3

  attr_accessor :skip_auto_audit, :auto_audit_destroy_snapshot
  normalize_phone_fields :corretor_telefone,
                         :proprietario_celular,
                         :proprietario_telefone_comercial,
                         :proprietario_telefone_residencial,
                         :zelador_telefone

  # Concerns organizados por responsabilidade
  include Habitation::PriceFormatting
  include Habitation::SearchScopes
  include Habitation::CacheableMethods
  include Habitation::SeoHelpers
  
  # Constantes Padronizadas para Enums e Atributos
  CATEGORIES = [
    'Apartamento', 'Casa', 'Casa em Condomínio', 'Cobertura', 'Sobrado',
    'Terreno', 'Terreno em Condomínio', 'Loft', 'Studio', 'Sala Comercial',
    'Loja', 'Prédio Comercial', 'Galpão', 'Área', 'Rural'
  ].freeze

  PUBLIC_FILTER_EXTRA_CATEGORIES = [
    'Diferenciado', 'Garden'
  ].freeze

  TITLE_CATEGORY_TERMS = (CATEGORIES + PUBLIC_FILTER_EXTRA_CATEGORIES).sort_by { |category| -category.length }.freeze

  STATUS_OPTIONS = [
    'Venda', 'Aluguel', 'Diária', 'Pendente', 'Lançamento', 'Suspenso',
    'Alugado imobiliária', 'Alugado terceiros',
    'Vendido imobiliária', 'Vendido terceiros'
  ].freeze

  # Mapeia variações que aparecem na Vista (case mixed, sinônimos, etc.) para os
  # valores canônicos em STATUS_OPTIONS. Usado pelo SyncPropertyService no import
  # e pela migration de normalização.
  STATUS_NORMALIZATION_MAP = {
    "venda"                => "Venda",
    "venda e aluguel"      => "Venda",
    "aluguel"              => "Aluguel",
    "locacao"              => "Aluguel",
    "locação"              => "Aluguel",
    "diaria"               => "Diária",
    "diária"               => "Diária",
    "pendente"             => "Pendente",
    "lancamento"           => "Lançamento",
    "lançamento"           => "Lançamento",
    "suspenso"             => "Suspenso",
    "alugado imobiliaria"  => "Alugado imobiliária",
    "alugado imobiliária"  => "Alugado imobiliária",
    "alugado terceiros"    => "Alugado terceiros",
    "vendido imobiliaria"  => "Vendido imobiliária",
    "vendido imobiliária"  => "Vendido imobiliária",
    "vendido terceiros"    => "Vendido terceiros"
  }.freeze

  PUBLIC_STATUSES = ['Venda', 'Aluguel', 'Locação', 'Locacao'].freeze
  INACTIVE_STATUS_KEYWORDS = %w[suspenso alugado vendido].freeze
  NUMERIC_CODIGO_SQL = "codigo ~ '^[0-9]+$'".freeze
  VISTA_REFERENCE_CODIGO_SQL = "#{NUMERIC_CODIGO_SQL} AND COALESCE(imovel_dwv, '') <> 'Sim'".freeze
  TEMPORARY_CODIGO_PREFIX = "RASCUNHO-".freeze
  STANDALONE_CATEGORIES_WITHOUT_DEVELOPMENT_NAME = %w[casa sobrado rural chacara sitio].freeze

  def self.normalize_status(value)
    return nil if value.blank?
    key = value.to_s.strip.downcase
    STATUS_NORMALIZATION_MAP[key] || value.to_s.strip
  end

  def self.standalone_category_without_development_name?(category)
    STANDALONE_CATEGORIES_WITHOUT_DEVELOPMENT_NAME.include?(category.to_s.parameterize)
  end

  def self.highest_numeric_codigo
    where(NUMERIC_CODIGO_SQL).maximum("codigo::bigint").to_i
  end

  def self.highest_vista_reference_codigo
    where(VISTA_REFERENCE_CODIGO_SQL).maximum("codigo::bigint").to_i
  end

  def self.next_automatic_codigo
    next_code = [highest_numeric_codigo, highest_vista_reference_codigo].max + 1
    next_code += 1 while exists?(codigo: next_code.to_s)
    next_code.to_s
  end

  def self.next_temporary_codigo
    loop do
      candidate = "#{TEMPORARY_CODIGO_PREFIX}#{SecureRandom.hex(8).upcase}"
      return candidate unless exists?(codigo: candidate)
    end
  end

  SITUATIONS = [
    'Pré Lançamento', 'Lançamento', 'Construção', 'Pronto para Morar',
    'Novo', 'Usado'
  ].freeze

  INTAKE_ORIGIN_BROKER = "broker_intake".freeze
  INTAKE_MODALITIES = %w[venda locacao_anual ambos locacao_diaria].freeze
  INTAKE_STATUSES = {
    "draft" => "Rascunho",
    "submitted_for_admin_review" => "Em revisão administrativa",
    "admin_approved" => "Aguardando aceite do corretor",
    "returned_to_broker" => "Devolvido ao corretor",
    "internal" => "Disponível internamente",
    "published" => "Liberado para site"
  }.freeze
  CATALOG_VISIBLE_INTAKE_STATUSES = %w[internal published].freeze
  PENDING_REVIEW_INTAKE_STATUSES = %w[submitted_for_admin_review admin_approved].freeze
  PENDING_WORKFLOW_INTAKE_STATUSES = %w[draft submitted_for_admin_review admin_approved returned_to_broker].freeze
  SITE_RELEASABLE_INTAKE_STATUSES = %w[admin_approved returned_to_broker internal].freeze
  PHOTO_FLOW_CHOICES = {
    "upload" => "Enviar fotos",
    "schedule" => "Agendar fotógrafo"
  }.freeze
  YES_NO_ANSWERS = {
    "sim" => "Sim",
    "nao" => "Não"
  }.freeze
  PHOTO_SCHEDULE_URL = "https://calendly.com/fotografias-saluteimoveis/30min".freeze
  MINIMUM_INTAKE_SALE_PRICE_CENTS = 10_000_00
  MINIMUM_INTAKE_RENT_PRICE_CENTS = 100_00
  STRATEGIC_TAX_PLACEHOLDER_CENTS = [1, 100].freeze
  PUBLIC_MAP_DISPLAY_MODES = {
    "inherit" => "Seguir padrão da conta",
    "hidden" => "Ocultar localização",
    "approximate" => "Exibir região aproximada",
    "exact" => "Exibir localização exata"
  }.freeze
  PUBLIC_STREET_VIEW_MODES = {
    "inherit" => "Seguir padrão da conta",
    "enabled" => "Permitir vista da rua",
    "disabled" => "Bloquear vista da rua"
  }.freeze

  validates :public_map_display_mode, inclusion: { in: PUBLIC_MAP_DISPLAY_MODES.keys }
  validates :public_street_view_mode, inclusion: { in: PUBLIC_STREET_VIEW_MODES.keys }

  def self.public_property_types
    (where(exibir_no_site_flag: true).distinct.pluck(:categoria).compact + PUBLIC_FILTER_EXTRA_CATEGORIES)
      .map(&:to_s)
      .map(&:strip)
      .reject(&:blank?)
      .uniq
      .sort
  end

  def self.public_filter_property_types_cache_key(tenant_id)
    "public_filter_property_types_v1/tenant/#{tenant_id}"
  end

  def self.public_filter_location_options_cache_key(tenant_id)
    "public_filter_location_options_v1/tenant/#{tenant_id}"
  end

  def self.public_sitemap_cache_key(tenant_id, base_url = nil)
    host_digest = ActiveSupport::Digest.hexdigest(base_url.to_s)
    "public_sitemap_xml_v1/tenant/#{tenant_id}/#{host_digest}"
  end

  def self.public_listing_count_cache_key(tenant_id, filters)
    digest = ActiveSupport::Digest.hexdigest(normalized_public_listing_count_filters(filters).to_json)
    "public_listing_count_v1/tenant/#{tenant_id}/#{digest}"
  end

  def self.clear_public_filter_cache_for_tenant(tenant_id)
    return if tenant_id.blank?

    Rails.cache.delete(public_filter_property_types_cache_key(tenant_id))
    Rails.cache.delete(public_filter_location_options_cache_key(tenant_id))
    clear_public_sitemap_cache_for_tenant(tenant_id)
    clear_public_listing_count_cache_for_tenant(tenant_id)
    clear_public_home_cache_for_tenant(tenant_id)
    Footer::QuickLinksService.clear_cache if defined?(Footer::QuickLinksService)
  end

  def self.clear_public_sitemap_cache_for_tenant(tenant_id)
    return if tenant_id.blank?
    return unless Rails.cache.respond_to?(:delete_matched)

    Rails.cache.delete_matched("public_sitemap_xml_v1/tenant/#{tenant_id}/*")
  rescue NotImplementedError
    nil
  end

  def self.clear_public_listing_count_cache_for_tenant(tenant_id)
    return if tenant_id.blank?
    return unless Rails.cache.respond_to?(:delete_matched)

    Rails.cache.delete_matched("public_listing_count_v1/tenant/#{tenant_id}/*")
  rescue NotImplementedError
    nil
  end

  def self.clear_public_home_cache_for_tenant(tenant_id)
    return if tenant_id.blank?
    return unless Rails.cache.respond_to?(:delete_matched)

    Rails.cache.delete_matched("public_home/tenant/#{tenant_id}/*")
  rescue NotImplementedError
    nil
  end

  def self.photography_schedule_url
    Setting.get("photography_schedule_url", "").to_s.strip
  end

  def self.normalized_public_listing_count_filters(filters)
    raw = if filters.respond_to?(:to_unsafe_h)
            filters.to_unsafe_h
          elsif filters.respond_to?(:to_h)
            filters.to_h
          else
            {}
          end

    normalize_public_listing_count_value(raw.deep_stringify_keys.except("action", "controller", "page", "sort"))
  end

  def self.normalize_public_listing_count_value(value)
    case value
    when Hash
      value.sort.to_h.transform_values { |item| normalize_public_listing_count_value(item) }
    when Array
      value
        .map { |item| normalize_public_listing_count_value(item) }
        .sort_by { |item| item.to_json }
    else
      value.to_s
    end
  end

  def inactive_for_admin_card?
    inactive_commercial_status?
  end

  def unavailable_for_duplicate_check?
    !exibir_no_site_flag? || inactive_for_admin_card?
  end

  def inactive_commercial_status?
    inactive_status_key.present?
  end

  # INTERNAL_FEATURES = [ ... ] (Deprecated in favor of AttributeOption)
  def self.internal_features
    tenant = Current.tenant || raise(ArgumentError, "Tenant obrigatório para listar características")
    tenant.attribute_options.where(context: 'habitation', category: 'feature').order(name: :asc).pluck(:name)
  end

  # EXTERNAL_FEATURES = [ ... ] (Deprecated in favor of AttributeOption)
  def self.external_features
    tenant = Current.tenant || raise(ArgumentError, "Tenant obrigatório para listar infraestruturas")
    tenant.attribute_options.where(context: 'habitation', category: 'infrastructure').order(name: :asc).pluck(:name)
  end

  # Endereço e Localização
  has_one :address, as: :addressable, dependent: :destroy
  accepts_nested_attributes_for :address, allow_destroy: true, reject_if: :all_blank
  
  # Delegations for backward compatibility
  delegate :logradouro, :numero, :complemento, :bairro, :cidade, :uf, :cep, :latitude, :longitude,
           :tipo_endereco, :bairro_comercial, :pais, :imediacoes,
           to: :address, prefix: false, allow_nil: true

  # Constants for Standardization
  STREET_TYPES = ["Avenida", "Rua", "Alameda", "Travessa", "Rodovia", "Estrada", "Servidão", "Beco", "Praça"].freeze
  UF_OPTIONS = ["SC", "PR", "SP", "RS", "RJ", "MG", "ES", "DF", "GO", "MS", "MT", "BA"].freeze
  FACES = ["Norte", "Sul", "Leste", "Oeste", "Nordeste", "Noroeste", "Sudeste", "Sudoeste"].freeze
  CONSTRUCTION_PROFILES = ["Econômico", "Médio", "Alto", "Luxo", "Super Luxo"].freeze
  VAGA_TYPES = ["Privativa", "Rotativa", "Coberta", "Descoberta", "Gaveta", "Dupla"].freeze
  
  # Novos Enums (Gap Analysis)
  OCUPACAO_STATUS = ["Desocupado", "Ocupado", "Inquilino", "Proprietário", "Reservado"].freeze
  ESTADO_CONSERVACAO = ["Novo", "Ótimo", "Bom", "Regular", "Seminovo", "Usado", "Reformado", "Original", "Em Obras", "Na Planta"].freeze
  TOPOGRAFIA_OPTIONS = ["Plano", "Aclive", "Declive", "Irregular"].freeze
  FOTO_CLASSIFICACAO = ["Profissionais", "Boas", "Aceitáveis", "Amadoras", "Não tem fotos"].freeze
  # Ambientes das fotos do imóvel (armazenados em blob.metadata["ambiente"]).
  # A ordem também é a ordem de exibição no select do modal de configuração.
  FOTO_AMBIENTES = [
    "Fachada", "Sala de estar", "Sala de jantar", "Sacada", "Cozinha",
    "Lavanderia", "Lavabo", "Quartos", "Banheiros", "Área externa", "Garagem", "Planta"
  ].freeze
  # Ordem canônica de organização das fotos por ambiente. Quartos/Banheiros são
  # intercalados (Quarto1, Banheiro1, Quarto2, ...) por organize_photos_by_ambiente!.
  FOTO_AMBIENTE_ORDER = [
    "Fachada", "Sala de estar", "Sala de jantar", "Sacada", "Cozinha",
    "Lavanderia", "Lavabo", "Quartos", "Banheiros", "Área externa", "Garagem", "Planta"
  ].freeze
  KEY_LOCATION_OPTIONS = ["Imobiliária", "Corretor(a)", "Proprietário", "Zelador", "Portaria", "Inquilino", "Outro"].freeze
  CAPTACAO_KEY_LOCATION_OPTIONS = {
    "imobiliaria" => "Imobiliária",
    "corretor" => "Corretor(a)",
    "proprietario" => "Proprietário",
    "zelador" => "Zelador",
    "portaria" => "Portaria",
    "inquilino" => "Inquilino",
    "outro" => "Outro"
  }.freeze
  RENTAL_GUARANTEE_METHOD_OPTIONS = ["Seguro fiança", "Caução", "Fiador", "Título de capitalização", "Garantidora", "A combinar"].freeze
  REGIAO_FOCO_OPTIONS = ["Sim", "Não"].freeze
  PORTAL_PUBLICATION_FIELDS = {
    "zapimoveis" => :publicar_zapimoveis,
    "vivareal_vrsync" => :publicar_viva_real_vrsync,
    "imovelweb" => :publicar_imovelweb,
    "imovelweb_2" => :publicar_imovelweb_2,
    "chavesnamao" => :publicar_chaves_na_mao,
    "casamineira" => :publicar_casa_mineira,
    "lais_ai" => :publicar_lais_ai,
    "netimoveis2" => :publicar_netimoveis_2
  }.freeze

  CHAVES_NA_MAO_DESTAQUE_OPTIONS = [["Sim", "sim"], ["Não", "nao"]].freeze
  CHAVES_NA_MAO_PERIODO_LOCACAO_OPTIONS = [
    ["Por Mês", "por_mes"],
    ["Por Dia", "por_dia"],
    ["Por Ano", "por_ano"],
    ["Por Semana", "por_semana"],
    ["Imóvel de Venda", "imovel_de_venda"]
  ].freeze
  CASA_MINEIRA_MODELO_OPTIONS = [
    ["Simples", "simples"],
    ["Destaque", "destaque"],
    ["Home Destaque", "home_destaque"]
  ].freeze
  VIVA_REAL_TIPO_PUBLICACAO_OPTIONS = [
    ["Padrão", "padrao"],
    ["Destaque", "destaque"],
    ["Super Destaque", "super_destaque"],
    ["Destaque Superior", "destaque_superior"],
    ["Destaque Exclusivo", "destaque_exclusivo"],
    ["Destaque Triplo", "destaque_triplo"]
  ].freeze
  VIVA_REAL_DIVULGAR_ENDERECO_OPTIONS = [
    ["Exata", "exata"],
    ["Rua", "rua"],
    ["Bairro", "bairro"]
  ].freeze
  IMOVELWEB_TIPO_PUBLICACAO_OPTIONS = [
    ["Simples", "simples"],
    ["Destaque", "destaque"],
    ["Super Destaque", "super_destaque"]
  ].freeze
  IMOVELWEB_MOSTRAR_MAPA_OPTIONS = [
    ["Exato", "exato"],
    ["Não mostrar", "nao_mostrar"],
    ["Aproximado", "aproximado"]
  ].freeze

  # FriendlyId para URLs amigáveis (SEO)
  extend FriendlyId
  friendly_id :slug_candidates, use: [:slugged, :finders]
  
  # Paginação
  self.per_page = 12
  
  belongs_to :empreendimento,
    ->(habitation) { where(tenant_id: habitation.tenant_id) },
    class_name: 'Habitation',
    primary_key: 'codigo',
    foreign_key: 'codigo_empreendimento',
    optional: true
  
  belongs_to :constructor, optional: true
  belongs_to :proprietor, optional: true
  belongs_to :admin_reviewed_by, class_name: "AdminUser", optional: true
  has_many :habitation_interactions, dependent: :nullify
  
  has_many :units,
    ->(habitation) { where(tenant_id: habitation.tenant_id) },
    class_name: 'Habitation',
    primary_key: 'codigo',
    foreign_key: 'codigo_empreendimento'
  
  # Active Storage Photos (For manual upload)
  has_many_attached :photos

  scope :with_local_photos, -> {
    where(<<~SQL.squish)
      EXISTS (
        SELECT 1
        FROM active_storage_attachments
        WHERE active_storage_attachments.record_id = habitations.id
          AND active_storage_attachments.record_type = 'Habitation'
          AND active_storage_attachments.name = 'photos'
      )
    SQL
  }
  scope :without_local_photos, -> { where.not(id: with_local_photos.select(:id)) }
  scope :with_operational_photos, -> {
    where(<<~SQL.squish)
      EXISTS (
        SELECT 1
        FROM active_storage_attachments
        WHERE active_storage_attachments.record_id = habitations.id
          AND active_storage_attachments.record_type = 'Habitation'
          AND active_storage_attachments.name = 'photos'
      )
      OR (
        LOWER(TRIM(COALESCE(habitations.imovel_dwv, ''))) = 'sim'
        AND jsonb_typeof(habitations.pictures) = 'array'
        AND jsonb_array_length(habitations.pictures) > 0
      )
    SQL
  }
  scope :without_operational_photos, -> { where.not(id: with_operational_photos.select(:id)) }
  scope :without_operational_address, -> {
    where("NULLIF(TRIM(COALESCE(addresses.logradouro, habitations.endereco)), '') IS NULL")
  }
  scope :without_operational_price, -> {
    where("COALESCE(habitations.tipo, '') <> ?", "Empreendimento")
      .where("COALESCE(habitations.valor_venda_cents, 0) <= 0 AND COALESCE(habitations.valor_locacao_cents, 0) <= 0")
  }
  has_many :ai_property_suggestions, dependent: :destroy
  has_many :habitation_audit_logs

  # Documentos internos do imóvel (só admin/editor enxergam — não vão para o site público)
  # Após anexar, AttachmentOrganizerService move os blobs para
  # imoveis/{codigo}/fichas-cadastro/ e imoveis/{codigo}/autorizacoes/ no DO Spaces.
  has_many_attached :fichas_cadastro
  has_many_attached :autorizacoes_venda

  after_commit :organize_document_attachments, on: %i[create update]

  def organize_document_attachments
    return unless fichas_cadastro.attached? || autorizacoes_venda.attached?
    Habitations::AttachmentOrganizerService.new(self).call
  end

  belongs_to :admin_user, optional: true, foreign_key: 'admin_user_id'
  
  has_many :broker_assignments, class_name: "HabitationBrokerAssignment", dependent: :destroy
  has_many :development_aliases, foreign_key: :development_id, dependent: :destroy, inverse_of: :development
  has_many :habitation_share_links, dependent: :destroy
  accepts_nested_attributes_for :broker_assignments, allow_destroy: true, reject_if: :all_blank

  # ActionText for Rich Text
  has_rich_text :descricao_web
  has_rich_text :meta_description

  # Validations
  validates :codigo, presence: true, uniqueness: { scope: :tenant_id }
  validates :categoria, presence: true
  validates :captador_commission_percentage,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :broker_commission_percentage,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :key_location, inclusion: { in: KEY_LOCATION_OPTIONS }, allow_blank: true
  validate :rental_guarantee_methods_must_be_valid
  validate :codigo_empreendimento_must_exist, if: :validate_codigo_empreendimento?
  validate :codigo_empreendimento_cannot_reference_self
  validate :key_location_notes_required_for_other
  validate :inactive_commercial_status_details_required
  
  # Callbacks
  before_validation :unpublish_when_commercial_status_inactive
  before_validation :clear_category_mismatched_slug, prepend: true
  before_validation :assign_codigo_automaticamente, on: :create
  before_validation :set_data_cadastro_crm, on: :create
  before_validation :normalize_codigo_empreendimento
  before_validation :clear_unlinked_standalone_development_name
  before_validation :sync_hierarchy_data
  before_validation :sync_construtora_from_constructor
  before_validation :sanitize_fields
  before_validation :clear_motivo_suspensao_unless_suspended
  before_save :capture_price_reductions
  before_update :stamp_preco_atualizado_em
  before_save :sync_flags_from_features
  before_save :sync_intake_answers
  after_save :clear_cache
  after_destroy :clear_cache
  after_create_commit :record_auto_audit_create, unless: :skip_auto_audit?
  after_update_commit :record_auto_audit_update, unless: :skip_auto_audit?
  after_update_commit :dispatch_interest_price_drop
  before_destroy :capture_auto_audit_destroy_snapshot, unless: :skip_auto_audit?
  after_destroy_commit :record_auto_audit_destroy, unless: :skip_auto_audit?

  scope :broker_intakes, -> { where(intake_origin: INTAKE_ORIGIN_BROKER) }
  scope :reassignable_broker_intakes_for_capture_layer_deactivation, -> { broker_intakes.where.not(intake_status: "published") }
  scope :pending_admin_review_from_intake, -> {
    broker_intakes.where(intake_status: PENDING_REVIEW_INTAKE_STATUSES)
  }

  def step
    intake_step.presence || "intro"
  end

  def completed?
    intake_status.in?(%w[submitted_for_admin_review admin_approved internal published])
  end

  def published_on_site?
    exibir_no_site_flag?
  end

  def submitted_at
    submitted_for_review_at
  end

  def rental_guarantee_method=(value)
    values = Array(value)
      .flatten
      .flat_map { |item| item.to_s.split(",") }
      .map(&:strip)
      .compact_blank
      .uniq

    super(values.join(", "))
  end

  def rental_guarantee_methods
    rental_guarantee_method.to_s.split(",").map(&:strip).compact_blank
  end

  def corretor
    admin_user
  end

  def primary_captador_assignment
    assignments = if broker_assignments.loaded?
                    broker_assignments.reject(&:marked_for_destruction?)
                  else
                    broker_assignments.includes(:admin_user)
                  end

    assignments.find { |assignment| assignment.role == "captador" && assignment.admin_user.present? }
  end

  def primary_captador
    primary_captador_assignment&.admin_user || admin_user || dwv_owner_user
  end

  def primary_captador_name
    primary_captador&.name.presence || corretor_nome.presence
  end

  def property_kind
    return "casa_rua" if street_house?
    return "terreno" if categoria.to_s.match?(/terreno/i)
    return "sala_comercial" if categoria.to_s.match?(/sala|loja|comercial|ponto|conjunto/i)
    return "galpao" if categoria.to_s.match?(/galp/i)
    "residencial"
  end

  def property_kind=(value)
    self.categoria = case value
                     when "sala_comercial" then "Sala Comercial"
                     when "terreno" then "Terreno"
                     else "Apartamento"
                     end
  end

  def property_kind_residencial?
    property_kind.in?(%w[residencial casa_rua])
  end

  def property_kind_sala_comercial?
    property_kind == "sala_comercial"
  end

  def property_kind_terreno?
    property_kind == "terreno"
  end

  def property_kind_galpao?
    property_kind == "galpao"
  end

  def property_kind_street_house?
    property_kind == "casa_rua"
  end

  def property_kind_apartment_unit?
    categoria.to_s.match?(/apartamento|cobertura|loft|studio/i)
  end

  def requires_parking_info?
    property_kind_apartment_unit?
  end

  def condominium_house?
    categoria.to_s.match?(/casa.*condom[ií]nio|condom[ií]nio.*casa/i)
  end

  def condominium_land?
    categoria.to_s.match?(/terreno.*condom[ií]nio|condom[ií]nio.*terreno/i)
  end

  def requires_unit_number?
    property_kind_apartment_unit?
  end

  def uses_building_infrastructure?
    property_kind_apartment_unit? || condominium_house?
  end

  def requires_intake_development_name?
    property_kind_apartment_unit? || condominium_house? || condominium_land?
  end

  def requires_intake_address_complement?
    requires_unit_number? ||
      condominium_house? ||
      property_kind_sala_comercial? ||
      property_kind_galpao? ||
      property_kind_terreno?
  end

  # Casa em condomínio localiza a unidade por lote/quadra dentro do empreendimento.
  def requires_intake_lot_block?
    condominium_house?
  end

  def intake_address_complement_label
    return "Unidade / Apto" if requires_unit_number?
    return "Complemento / Casa" if condominium_house?
    return "Complemento / Sala" if property_kind_sala_comercial?

    "Complemento"
  end

  def intake_address_complement_placeholder
    return "1203" if requires_unit_number?
    return "Ex.: Casa 12" if condominium_house?
    return "Ex.: Sala 402" if property_kind_sala_comercial?
    return "Ex.: Galpão B, fundos" if property_kind_galpao?
    return "Ex.: Lote 12, Quadra B" if property_kind_terreno?

    "Ex.: fundos, sala, lote..."
  end

  def street_house?
    categoria.to_s.match?(/\bcasa\b|sobrado|rural|chácara|chacara|sítio|sitio/i)
  end

  def has_required_intake_area?
    return area_total_m2.to_f.positive? if property_kind_terreno?

    area_privativa_m2.to_f.positive?
  end

  def requires_intake_expense_amount?
    !property_kind_terreno? && !property_kind_sala_comercial? && !property_kind_galpao?
  end

  def requires_intake_key_location?
    !property_kind_terreno?
  end

  def duplicate_identity_scope
    if (condominium_house? || property_kind_terreno?) && (complemento.present? || bloco.present?)
      return :condominium_unit
    end

    requires_unit_number? || bloco.present? ? :unit : :street
  end

  def modalidade
    return intake_modalidade if intake_modalidade.in?(INTAKE_MODALITIES)

    if valor_venda_cents.to_i.positive? && valor_locacao_cents.to_i.positive?
      "ambos"
    elsif rental_intake?
      "locacao_anual"
    else
      "venda"
    end
  end

  def modalidade=(value)
    normalized = value.to_s.presence_in(INTAKE_MODALITIES)
    self.intake_modalidade = normalized
    self.status = normalized.in?(%w[locacao_anual locacao_diaria]) ? "Aluguel" : "Venda"
  end

  def requires_sale_price?
    modalidade.in?(%w[venda ambos])
  end

  def requires_rent_price?
    modalidade.in?(%w[locacao_anual locacao_diaria ambos])
  end

  def valid_intake_sale_price?
    valor_venda_cents.to_i >= MINIMUM_INTAKE_SALE_PRICE_CENTS
  end

  def valid_intake_rent_price?
    valor_locacao_cents.to_i >= MINIMUM_INTAKE_RENT_PRICE_CENTS
  end

  def intake_sale_price_requirement_message
    "Informe um valor de venda válido (mínimo R$ 10.000)."
  end

  def intake_rent_price_requirement_message
    "Informe um valor de locação válido (mínimo R$ 100)."
  end

  def skip_visitas?
    property_kind_terreno?
  end

  def progress_percentage
    total = Captacao::STEPS.size
    current = Captacao::STEPS.index(step).to_i + 1
    ((current.to_f / total) * 100).round
  end

  def previous_step
    idx = Captacao::STEPS.index(step)
    return nil if idx.blank? || idx.zero?
    Captacao::STEPS[idx - 1]
  end

  def next_step
    idx = Captacao::STEPS.index(step).to_i
    Captacao::STEPS[[idx + 1, Captacao::STEPS.size - 1].min]
  end

  def zip_code = cep
  def street = logradouro
  def street_number = numero
  def neighborhood = bairro
  def city = cidade
  def state = uf

  def edificio_nome = nome_empreendimento
  def unidade_numero = bloco

  def proprietario_nome = proprietario
  def proprietario_telefone
    proprietario_celular.presence ||
      proprietor&.mobile_phone.presence ||
      proprietor&.phone_primary.presence ||
      proprietor&.business_phone.presence ||
      proprietor&.residential_phone.presence
  end

  def proprietario_telefone_comercial_display
    proprietario_telefone_comercial.presence || proprietor&.business_phone
  end

  def proprietario_telefone_residencial_display
    proprietario_telefone_residencial.presence || proprietor&.residential_phone
  end

  def proprietario_cpf_cnpj = proprietario_codigo
  def proprietario_cidade = captacao_note_value("Cidade do proprietário")

  def area_total = area_total_m2
  def area_privativa = area_privativa_m2
  def dormitorios = dormitorios_qtd
  def suites = suites_qtd
  def demi_suites = demi_suites_qtd
  def banheiros = banheiros_qtd
  def vagas_garagem = vagas_qtd
  def salas = salas_qtd

  def valor_venda = valor_venda_cents.to_i.positive? ? valor_venda_cents / 100.0 : nil
  def valor_locacao = valor_locacao_cents.to_i.positive? ? valor_locacao_cents / 100.0 : nil
  def valor_condominio = valor_condominio_cents.to_i.positive? ? valor_condominio_cents / 100.0 : nil
  def valor_iptu = valor_iptu_cents.to_i.positive? ? valor_iptu_cents / 100.0 : nil
  def saldo_devedor = saldo_devedor_cents.to_i.positive? ? saldo_devedor_cents / 100.0 : nil

  def displayable_condominio_cents
    displayable_tax_cents(valor_condominio_cents)
  end

  def displayable_iptu_cents
    displayable_tax_cents(valor_iptu_cents)
  end

  def taxes_included_indicator?
    valor_locacao_cents.to_i.positive? &&
      displayable_condominio_cents.blank? && displayable_iptu_cents.blank?
  end

  def rent_discount?
    valor_locacao_cents.to_i.positive? &&
      valor_locacao_anterior_cents.to_i > valor_locacao_cents.to_i
  end

  def sale_discount?
    valor_venda_cents.to_i.positive? &&
      valor_venda_anterior_cents.to_i > valor_venda_cents.to_i
  end

  def caracteristicas_imovel = normalize_captacao_list(caracteristicas, category: "feature")
  def caracteristicas_predio = normalize_captacao_list(infra_estrutura, category: "infrastructure")
  def aceita_permuta
    aceita_permuta_answer == "sim" || aceita_permuta_flag? ? ["Sim"] : []
  end
  def aceita_parcelamento = aceita_parcelamento_flag? ? "sim" : "nao"
  def outras_taxas = captacao_note_list("Outras taxas")
  def dias_visitas = captacao_note_list("Dias/horários para visita")
  def intake_visit_days_present? = dias_visitas.any?
  def extras
    {
      "frente_metros" => dimensoes_terreno.to_s[/Frente:\s*([^|]+)/, 1]&.strip&.delete_suffix(" m"),
      "topografia" => topografia.to_s.parameterize(separator: "_"),
      "face" => face
    }.compact_blank
  end
  def chaves_com
    CAPTACAO_KEY_LOCATION_OPTIONS.key(key_location)
  end
  def senha_imovel = captacao_note_value("Senha do imóvel")
  def senha_portaria = captacao_note_value("Senha da portaria")

  def senha_imovel=(value)
    set_captacao_note_value("Senha do imóvel", value)
  end

  def senha_portaria=(value)
    set_captacao_note_value("Senha da portaria", value)
  end

  def ocupacao = ocupacao_status
  def estado_imovel = estado_conservacao
  def situacao_imovel = situacao
  def sacada = captacao_feature_enabled?("Sacada")
  def terraco = captacao_feature_enabled?("Terraço")
  def dependencia_empregada = captacao_feature_enabled?("Dependência de empregada")
  def precisa_reforma = captacao_feature_enabled?("Precisa reforma")
  def andares_total = andares_qtd
  def aptos_por_andar = aptos_andar
  def distancia_praia = captacao_note_value("Distância da praia").to_s.delete_suffix(" m")
  def cidade_permuta = permuta_localizacao
  def fotos = photos
  def autorizacao_pdf = autorizacoes_venda.attachments.first

  {
    zip_code: [:address, :cep],
    street: [:address, :logradouro],
    street_number: [:address, :numero],
    neighborhood: [:address, :bairro],
    city: [:address, :cidade],
    state: [:address, :uf],
    edificio_nome: [:self, :nome_empreendimento],
    unidade_numero: [:self, :bloco],
    proprietario_nome: [:self, :proprietario],
    proprietario_telefone: [:self, :proprietario_celular],
    proprietario_cpf_cnpj: [:self, :proprietario_codigo],
    area_total: [:self, :area_total_m2],
    area_privativa: [:self, :area_privativa_m2],
    dormitorios: [:self, :dormitorios_qtd],
    suites: [:self, :suites_qtd],
    demi_suites: [:self, :demi_suites_qtd],
    banheiros: [:self, :banheiros_qtd],
    vagas_garagem: [:self, :vagas_qtd],
    salas: [:self, :salas_qtd],
    caracteristicas_imovel: [:self, :caracteristicas],
    caracteristicas_predio: [:self, :infra_estrutura],
    ocupacao: [:self, :ocupacao_status],
    estado_imovel: [:self, :estado_conservacao],
    situacao_imovel: [:self, :situacao],
    andares_total: [:self, :andares_qtd],
    aptos_por_andar: [:self, :aptos_andar],
    cidade_permuta: [:self, :permuta_localizacao]
  }.each do |method_name, (target, attribute)|
    define_method("#{method_name}=") do |value|
      receiver = target == :address ? ensure_address : self
      receiver.public_send("#{attribute}=", value)
    end
  end

  def captacao_note_value(label)
    observacoes_visitas.to_s.each_line do |line|
      key, value = line.split(":", 2)
      return value.to_s.strip if key == label
    end
    nil
  end

  def proprietario_cidade=(value)
    set_captacao_note_value("Cidade do proprietário", value)
  end

  def captacao_note_list(label)
    captacao_note_value(label).to_s.split(",").map(&:strip).compact_blank
  end

  def captacao_feature_enabled?(label)
    values = caracteristicas.is_a?(Hash) ? caracteristicas.to_a.flatten : Array(caracteristicas)
    values.any? { |value| value.to_s.casecmp?(label) }
  end

  def set_captacao_note_value(label, value)
    lines = observacoes_visitas.to_s.lines.map(&:chomp).reject { |line| line.start_with?("#{label}:") }
    lines << "#{label}: #{value}" if value.present?
    self.observacoes_visitas = lines.join("\n")
  end

  {
    valor_venda: :valor_venda_formatted,
    valor_locacao: :valor_locacao_formatted,
    valor_condominio: :valor_condominio_formatted,
    valor_iptu: :valor_iptu_formatted,
    saldo_devedor: :saldo_devedor_formatted,
    valor_comissao: :valor_comissao_formatted,
    valor_livre_proprietario: :valor_livre_proprietario_formatted,
    valor_alugado_terceiros: :valor_alugado_terceiros_formatted,
    valor_vendido_terceiros: :valor_vendido_terceiros_formatted
  }.each do |method_name, formatted_attribute|
    define_method("#{method_name}=") { |value| public_send("#{formatted_attribute}=", value) }
  end

  def aceita_permuta=(value)
    self.aceita_permuta_answer = Array(value).include?("Sim") ? "sim" : "nao"
  end

  def aceita_parcelamento=(value)
    self.aceita_parcelamento_flag = value != "nao"
  end

  def ensure_address
    address || build_address
  end

  def preco_principal
    if valor_venda_cents.to_i > 0
      ActiveSupport::NumberHelper.number_to_currency(valor_venda_cents / 100.0, precision: 0)
    elsif valor_locacao_cents.to_i > 0
      "#{ActiveSupport::NumberHelper.number_to_currency(valor_locacao_cents / 100.0, precision: 0)}/mês"
    else
      "Sob Consulta"
    end
  end

  def tipo_transacao
    if status.to_s.downcase.include?('locacao') || status.to_s.downcase.include?('aluguel')
      'Locação'
    else
      'Venda'
    end
  end

  def displayable_tax_cents(value)
    cents = value.to_i
    return nil if cents <= 0 || STRATEGIC_TAX_PLACEHOLDER_CENTS.include?(cents)

    cents
  end

  def self.portal_publication_column_for(portal_key)
    PORTAL_PUBLICATION_FIELDS[portal_key.to_s]
  end

  def broker_intake?
    intake_origin == INTAKE_ORIGIN_BROKER
  end

  def temporary_codigo?
    codigo.to_s.start_with?(TEMPORARY_CODIGO_PREFIX)
  end

  def finalize_broker_intake_registration!(submitted_at: Time.current)
    return unless broker_intake?

    if codigo.blank? || temporary_codigo?
      self.codigo = self.class.next_automatic_codigo
      self.slug = nil
      self.data_cadastro_crm = submitted_at || Time.current
    else
      self.data_cadastro_crm ||= submitted_at || Time.current
    end
  end

  def intake_status_label
    INTAKE_STATUSES[intake_status] || intake_status.to_s.humanize
  end

  def intake_draft?
    intake_status.blank? || intake_status == "draft"
  end

  def intake_submitted_for_admin_review?
    intake_status == "submitted_for_admin_review"
  end

  def intake_admin_approved?
    intake_status == "admin_approved"
  end

  def broker_release_pending?
    SITE_RELEASABLE_INTAKE_STATUSES.include?(intake_status)
  end

  def broker_responsible_for?(user)
    return false if user.nil?
    return true if admin_user_id == user.id

    if broker_assignments.loaded?
      broker_assignments.any? { |assignment| assignment.admin_user_id == user.id }
    else
      broker_assignments.exists?(admin_user_id: user.id)
    end
  end

  def intake_internal?
    intake_status == "internal"
  end

  def intake_published?
    intake_status == "published"
  end

  def has_any_photo?
    if attached_photos_loaded?
      photos_attachments.any? || image_urls.any?
    else
      photos.attached? || image_urls.any?
    end
  end

  def has_local_photo?
    attached_photos_loaded? ? photos_attachments.any? : photos.attached?
  end

  def has_operational_photo?
    has_local_photo? || has_dwv_remote_photo?
  end

  def has_dwv_remote_photo?
    dwv_property? && pictures.is_a?(Array) && pictures.any? do |picture|
      if picture.respond_to?(:[])
        picture["url"].presence || picture[:url].presence || picture["src"].presence || picture[:src].presence
      else
        picture.to_s.presence
      end
    end
  end

  def missing_operational_address?
    endereco.blank? && (address.blank? || address.logradouro.blank?)
  end

  def missing_operational_price?
    !empreendimento? && !has_public_price?
  end

  def hidden_from_site_with_photos?
    has_any_photo? && !exibir_no_site_flag?
  end

  def rental_intake?
    modalidade = intake_modalidade.presence
    return true if modalidade.in?(%w[locacao_anual locacao_diaria ambos])
    return false if modalidade == "venda"

    status.to_s.downcase.match?(/aluguel|loca/)
  end

  def sale_intake?
    modalidade = intake_modalidade.presence
    return true if modalidade.in?(%w[venda ambos])

    !rental_intake?
  end

  def whatsapp_negotiation_type
    has_sale_price = valor_venda_cents.to_i.positive?
    has_rent_price = valor_locacao_cents.to_i.positive?

    return "sale_rent" if intake_modalidade == "ambos" || (has_sale_price && has_rent_price)
    return "rent" if rental_intake? || has_rent_price

    "sale"
  end

  def intake_missing_requirements(required_checks: nil, require_owner_city: false)
    operational_checks = Array(required_checks).present?
    required_checks = Array(required_checks).presence || PropertySetting.default_broker_capture_checks
    # Aceita tanto o formato granular atual quanto blocos legados (expande quando necessário).
    required_checks = PropertySetting.normalize_intake_checks(required_checks)
    check = ->(key) { required_checks.include?(key) }
    owner_city_required = check.call("proprietario_cidade") || (!operational_checks && require_owner_city)

    missing = []
    missing << "Dados do proprietário" if check.call("proprietario") && intake_owner_data_missing?(require_owner_city: false)
    missing << "Cidade do proprietário" if owner_city_required && proprietario_cidade.blank?
    missing << "Endereço e localização" if check.call("endereco") && (address.blank? || cep.blank? || logradouro.blank? || bairro.blank? || cidade.blank? || uf.blank?)
    missing << "Empreendimento" if check.call("empreendimento") && requires_intake_development_name? && nome_empreendimento.blank?
    missing << "Número da unidade" if check.call("unidade") && requires_unit_number? && bloco.blank?
    missing << "Complemento" if check.call("endereco") && requires_intake_address_complement? && !requires_unit_number? && complemento.blank?
    missing << "Definições básicas" if check.call("definicoes") && (categoria.blank? || status.blank?)
    missing << "Título do anúncio" if check.call("titulo") && titulo_anuncio.blank?
    missing << "Título do anúncio coerente com a categoria" if check.call("titulo_categoria") && title_category_inconsistent?
    missing << "Descrição do imóvel" if check.call("descricao") && display_description_plain_text.blank?
    if check.call("area")
      if property_kind_terreno?
        missing << "Dimensões e estrutura física" if area_total_m2.to_f <= 0
      elsif property_kind_sala_comercial?
        missing << "Dimensões e estrutura física" if area_privativa_m2.to_f <= 0 && salas_qtd.to_i <= 0 && banheiros_qtd.to_i <= 0 && vagas_qtd.to_i <= 0
      elsif !has_required_intake_area?
        missing << "Área privativa" if area_privativa_m2.to_f <= 0
      elsif property_kind_residencial? && dormitorios_qtd.to_i <= 0 && suites_qtd.to_i <= 0 && vagas_qtd.to_i <= 0
        missing << "Dimensões e estrutura física"
      end
    end
    if requires_parking_info?
      missing << "Tipo de vaga" if check.call("tipo_vaga") && tipo_vaga.blank?
      missing << "Vaga de garagem" if check.call("vagas") && vagas_qtd.nil?
      missing << "Box" if check.call("box") && vagas_qtd.to_i.positive? && numero_box.blank?
    end
    missing << "Situação" if check.call("situacao") && !property_kind_terreno? && situacao.blank?
    missing << "Ocupação" if check.call("ocupacao") && !property_kind_terreno? && ocupacao_status.blank?
    missing << "Mais características" if check.call("caracteristicas") && caracteristicas.blank?
    missing << "Infraestrutura & Lazer" if check.call("infraestrutura") && uses_building_infrastructure? && infra_estrutura.blank?
    missing << intake_sale_price_requirement_message if check.call("valor_negociacao") && requires_sale_price? && !valid_intake_sale_price?
    missing << intake_rent_price_requirement_message if check.call("valor_negociacao") && requires_rent_price? && !valid_intake_rent_price?
    missing << "Financeiro e valores" if check.call("financeiro") && requires_intake_expense_amount? && valor_condominio_cents.blank? && valor_iptu_cents.blank?
    missing << "Administração da locação" if check.call("admin_locacao") && rental_intake? && salute_rental_management_answer.blank?
    missing << "Meio de garantia locatícia" if check.call("garantia_locaticia") && rental_intake? && rental_guarantee_method.blank?
    missing << "Aceita permuta" if check.call("permuta") && sale_intake? && aceita_permuta_answer.blank?
    missing << "Quantidade de parcelas" if check.call("parcelamento") && aceita_parcelamento_flag? && numero_prestacoes.blank?
    missing << "Chaves" if check.call("chaves") && requires_intake_key_location? && key_location.blank?
    missing << "Dias de visita" if check.call("visitas") && !skip_visitas? && !intake_visit_days_present?
    missing << "Fotos ou agenda com fotógrafo" if check.call("fotos") && photo_flow_choice == "upload" && !has_any_photo?
    missing << "Agenda com fotógrafo" if check.call("fotos") && photo_flow_choice == "schedule" && photo_session_requested_at.blank?
    missing << "Fotos ou agenda com fotógrafo" if check.call("fotos") && photo_flow_choice.blank? && !has_any_photo?
    missing << "Anexo da autorização do proprietário" if check.call("autorizacao") && !autorizacoes_venda.attached?
    missing
  end

  def intake_owner_data_missing?(require_owner_city: false)
    owner_name = proprietario.presence || proprietor&.name
    owner_contact = proprietario_celular.presence || proprietario_telefone.presence || proprietario_email.presence || proprietor&.mobile_phone || proprietor&.phone_primary || proprietor&.email

    owner_name.blank? || owner_contact.blank? || (require_owner_city && proprietario_cidade.blank?)
  end

  def intake_ready_for_admin_review?(required_checks: nil, require_owner_city: false)
    intake_missing_requirements(required_checks: required_checks, require_owner_city: require_owner_city).empty?
  end

  def intake_returned_to_broker?
    intake_status == "returned_to_broker"
  end

  def review_return_count
    @review_return_count ||= habitation_audit_logs
      .where(action: "intake_status_changed")
      .where("changeset -> 'intake_status' ->> 'after' = ?", "returned_to_broker")
      .count
  end

  def review_return_count_warning_threshold
    REVIEW_RETURN_WARNING_THRESHOLD
  end

  def review_return_count_warning?
    review_return_count >= review_return_count_warning_threshold
  end

  def review_returned_in_last_30_days?
    review_return_count_in_last_30_days.positive?
  end

  def review_return_count_in_last_30_days
    @review_return_count_in_last_30_days ||= habitation_audit_logs
      .where(action: "intake_status_changed")
      .where("changeset -> 'intake_status' ->> 'after' = ?", "returned_to_broker")
      .where("created_at >= ?", 30.days.ago)
      .count
  end

  def broker_can_release_to_site?(required_checks: nil)
    intake_admin_approved? && intake_ready_for_admin_review?(required_checks: required_checks, require_owner_city: true)
  end

  def intake_display_title
    title_category_inconsistent? ? default_title : display_title
  end

  def title_category_inconsistent?
    return false if titulo_anuncio.blank? || categoria.blank?

    title_category = title_category_terms_in_title.first
    return false if title_category.blank?

    title_category_key = normalize_title_category(title_category)
    current_category_key = normalize_title_category(categoria)
    return false if title_category_key == current_category_key

    !current_category_key.start_with?(title_category_key) && !title_category_key.start_with?(current_category_key)
  end

  def display_description_plain_text
    ActionController::Base.helpers.strip_tags(display_description.to_s).squish
  end
  
  # Retorna a URL da imagem principal
  def primary_image_url
    Storage::PublicCdnImageUrl.resolve(primary_image)
  end

  def primary_image_source
    public_image_sources.first
  end

  def card_image_sources(limit = 5)
    public_image_sources.first(limit)
  end

  # Retorna lista de URLs de todas as imagens
  def image_urls
    all_images.filter_map { |img| Storage::PublicCdnImageUrl.resolve(img) }
  end
  
  # Retorna a primeira imagem do imóvel (Hash format)
  def primary_image
    public_image_sources.first
  end

  def public_image_sources
    own_sources = own_public_image_sources
    return own_sources if empreendimento? || codigo_empreendimento.blank?
    return own_sources if own_sources.present? || !use_development_photos?

    (own_sources + linked_development_public_image_sources).uniq do |source|
      public_image_source_key(source)
    end
  end

  def own_public_image_sources
    attached_images = public_ordered_photos.map { |photo| { "attachment" => photo } }
    api_images = image_payload_sources

    attached_images.presence || api_images
  end

  def use_development_photos?
    use_development_photos_flag? && !empreendimento? && codigo_empreendimento.present?
  end

  def linked_development_public_image_sources
    return [] if empreendimento? || codigo_empreendimento.blank?

    empreendimento&.own_public_image_sources.presence || development_image_payload_sources
  end
  
  # Retorna todas as imagens (Hash format)
  def all_images
    public_image_sources
  end

  def image_payload_sources
    images = if empreendimento?
               fotos_empreendimento.present? ? fotos_empreendimento : pictures
             else
               pictures
             end

    if images.is_a?(Array)
      images.filter_map do |pic|
        payload = pic.is_a?(Hash) ? pic.deep_dup : { "url" => pic }
        payload["_habitation_id"] = id
        payload["_habitation_codigo"] = codigo
        payload if !picture_hidden_from_site?(payload) && Storage::PublicCdnImageUrl.resolve(payload).present?
      end
    else
      []
    end
  end

  def development_image_payload_sources
    return [] unless fotos_empreendimento.is_a?(Array)

    fotos_empreendimento.filter_map do |pic|
      payload = pic.is_a?(Hash) ? pic.deep_dup : { "url" => pic }
      payload["_habitation_id"] = id
      payload["_habitation_codigo"] = codigo
      payload if !picture_hidden_from_site?(payload) && Storage::PublicCdnImageUrl.resolve(payload).present?
    end
  end

  def public_image_source_key(source)
    attachment = source.try(:[], "attachment") || source.try(:[], :attachment)
    return "attachment:#{attachment.id}" if attachment&.id

    source.try(:[], "url") || source.try(:[], :url) || source.object_id
  end

  # Photo Sorting Logic
  def ordered_photo_ids=(ids)
    ids = ids.split(',') if ids.is_a?(String)
    # Ensure IDs are integers and unique, reject blanks
    self.photo_ids_order = ids.compact.map(&:to_i).uniq - [0]
  end

  def site_hidden_photo_ids=(ids)
    ids = ids.split(",") if ids.is_a?(String)
    super(Array(ids).filter_map { |id| id.to_s.strip.match?(/\A\d+\z/) ? id.to_i : nil }.uniq)
  end

  def site_hidden_picture_urls=(urls)
    return unless pictures.is_a?(Array)

    hidden_urls = Array(urls).flat_map { |url| url.to_s.split(",") }.map(&:strip).reject(&:blank?).uniq
    self.pictures = pictures.map do |picture|
      payload = picture.is_a?(Hash) ? picture.deep_dup : { "url" => picture }
      payload["site_hidden"] = hidden_urls.include?(picture_url_for_visibility(payload))
      payload
    end
  end

  def ordered_picture_indices=(indices)
    return unless pictures.is_a?(Array)

    indexes = indices.is_a?(String) ? indices.split(",") : Array(indices)
    ordered_indexes = indexes.filter_map do |raw_index|
      raw_index = raw_index.to_s.strip
      next unless raw_index.match?(/\A\d+\z/)

      index = raw_index.to_i
      index if index < pictures.length
    end.uniq

    return if ordered_indexes.blank?

    ordered_pictures = ordered_indexes.map { |index| pictures[index] }
    remaining_pictures = pictures.each_with_index.filter_map do |picture, index|
      picture unless ordered_indexes.include?(index)
    end

    self.pictures = ordered_pictures + remaining_pictures
  end

  def picture_ambiente(picture)
    value = picture.try(:[], "ambiente") || picture.try(:[], :ambiente)
    value.to_s.presence
  end

  def picture_ambiente_position(picture)
    value = picture.try(:[], "ambiente_position") || picture.try(:[], :ambiente_position)
    value = value.to_i
    value.positive? ? value : nil
  end

  def picture_ambiente_label(picture, index: nil)
    ambiente = picture_ambiente(picture)
    return nil if ambiente.blank?

    unless %w[Quartos Banheiros].include?(ambiente)
      return ambiente
    end

    singular = ambiente == "Quartos" ? "Quarto" : "Banheiro"
    position = 0
    pictures.to_a.each_with_index do |entry, entry_index|
      next unless picture_ambiente(entry) == ambiente

      position += 1
      return "#{singular} #{position}" if index.present? ? entry_index == index.to_i : picture_url_for_visibility(entry) == picture_url_for_visibility(picture)
    end

    ambiente
  end

  def set_picture_ambiente!(index, value, position: nil)
    return false unless pictures.is_a?(Array)

    picture_index = index.to_i
    return false unless picture_index >= 0 && picture_index < pictures.length

    normalized = value.to_s.strip
    normalized_position = position.to_s.strip

    self.pictures = pictures.each_with_index.map do |picture, current_index|
      next picture unless current_index == picture_index

      payload = picture.is_a?(Hash) ? picture.deep_dup : { "url" => picture.to_s }
      if normalized.blank?
        payload.delete("ambiente")
        payload.delete("ambiente_position")
      else
        payload["ambiente"] = normalized
        if normalized_position.match?(/\A\d+\z/) && normalized_position.to_i.positive?
          payload["ambiente_position"] = normalized_position.to_i
        else
          payload.delete("ambiente_position")
        end
      end
      payload
    end

    save!(validate: false)
    true
  end

  def ordered_photos
    attached_photos = attached_photos_for_display
    return attached_photos unless photo_ids_order.present? && attached_photos.any?
    
    # Sort them in memory according to the ID list
    # Photos not in the list go to the end
    attached_photos.sort_by do |photo|
      idx = photo_ids_order.index(photo.id)
      idx || 999999 # Place unordered photos at the end
    end
  end

  def public_ordered_photos
    hidden_ids = Array(site_hidden_photo_ids).map(&:to_i)
    ordered_photos.reject { |photo| hidden_ids.include?(photo.id) }
  end

  # --- Fotos por ambiente (metadata do blob) ---

  # Lê o ambiente gravado no metadata do blob da foto. String ∈ FOTO_AMBIENTES ou nil.
  def photo_ambiente(attachment)
    return nil unless attachment&.blob

    value = attachment.blob.metadata.to_h["ambiente"]
    value.presence
  end

  def photo_ambiente_position(attachment)
    return nil unless attachment&.blob

    value = attachment.blob.metadata.to_h["ambiente_position"].to_i
    value.positive? ? value : nil
  end

  # Grava o ambiente no metadata do blob (merge, preservando o resto). Valor nil/""
  # limpa o ambiente. Persiste o blob.
  def set_photo_ambiente!(attachment, value, position: nil)
    return unless attachment&.blob

    blob = attachment.blob
    metadata = blob.metadata.to_h
    normalized = value.to_s.strip
    normalized_position = position.to_s.strip

    if normalized.blank?
      metadata.delete("ambiente")
      metadata.delete("ambiente_position")
    else
      metadata["ambiente"] = normalized
      if normalized_position.match?(/\A\d+\z/) && normalized_position.to_i.positive?
        metadata["ambiente_position"] = normalized_position.to_i
      else
        metadata.delete("ambiente_position")
      end
    end

    blob.update!(metadata: metadata)
    association(:photos_attachments).reset if attached_photos_loaded?
  end

  # Rótulo de exibição com numeração automática de Quartos/Banheiros. Entre as fotos
  # (na ordem atual) com ambiente "Quartos", esta é a Nª => "Quarto N"; idem
  # "Banheiros" => "Banheiro N". Demais ambientes => o próprio nome; nil => nil.
  def photo_ambiente_label(attachment)
    ambiente = photo_ambiente(attachment)
    return nil if ambiente.blank?

    unless %w[Quartos Banheiros].include?(ambiente)
      return ambiente
    end

    singular = ambiente == "Quartos" ? "Quarto" : "Banheiro"
    position = 0
    ordered_photos.each do |photo|
      next unless photo_ambiente(photo) == ambiente

      position += 1
      return "#{singular} #{position}" if photo.id == attachment.id
    end

    ambiente
  end

  # Reordena photo_ids_order pela FOTO_AMBIENTE_ORDER, intercalando Quarto N com
  # Banheiro N. Fotos sem ambiente vão para o fim, preservando a ordem relativa
  # atual. Persiste a nova ordem.
  def organize_photos_by_ambiente!
    association(:photos_attachments).reset if attached_photos_loaded?
    photos_in_order = ordered_photos
    organize_pictures_by_ambiente!
    return if photos_in_order.blank?

    grouped = Hash.new { |hash, key| hash[key] = [] }
    unassigned = []

    photos_in_order.each do |photo|
      ambiente = photo_ambiente(photo)
      if ambiente.present? && FOTO_AMBIENTE_ORDER.include?(ambiente)
        grouped[ambiente] << [photo, photo_ambiente_position(photo)]
      else
        unassigned << photo
      end
    end

    ordered = []
    FOTO_AMBIENTE_ORDER.each do |ambiente|
      if ambiente == "Quartos"
        # Intercala Quarto N / Banheiro N (pares), depois sobras de cada um.
        quartos = ordered_ambiente_photos(grouped["Quartos"])
        banheiros = ordered_ambiente_photos(grouped["Banheiros"])
        [quartos.size, banheiros.size].max.times do |index|
          ordered << quartos[index] if quartos[index]
          ordered << banheiros[index] if banheiros[index]
        end
      elsif ambiente == "Banheiros"
        next # já intercalado junto de "Quartos"
      else
        ordered.concat(ordered_ambiente_photos(grouped[ambiente]))
      end
    end

    ordered.concat(unassigned)

    self.photo_ids_order = ordered.map(&:id)
    save!(validate: false)
  end

  def organize_pictures_by_ambiente!
    return unless pictures.is_a?(Array)
    return if pictures.blank?

    grouped = Hash.new { |hash, key| hash[key] = [] }
    unassigned = []

    pictures.each do |picture|
      ambiente = picture_ambiente(picture)
      if ambiente.present? && FOTO_AMBIENTE_ORDER.include?(ambiente)
        grouped[ambiente] << [picture, picture_ambiente_position(picture)]
      else
        unassigned << picture
      end
    end

    ordered = []
    FOTO_AMBIENTE_ORDER.each do |ambiente|
      if ambiente == "Quartos"
        quartos = ordered_ambiente_pictures(grouped["Quartos"])
        banheiros = ordered_ambiente_pictures(grouped["Banheiros"])
        [quartos.size, banheiros.size].max.times do |index|
          ordered << quartos[index] if quartos[index]
          ordered << banheiros[index] if banheiros[index]
        end
      elsif ambiente == "Banheiros"
        next
      else
        ordered.concat(ordered_ambiente_pictures(grouped[ambiente]))
      end
    end

    self.pictures = ordered + unassigned
    save!(validate: false)
  end

  def ordered_ambiente_photos(entries)
    entries.each_with_index
      .sort_by { |(_photo, position), index| [position.present? ? 0 : 1, position || index, index] }
      .map { |(photo, _position), _index| photo }
  end

  def ordered_ambiente_pictures(entries)
    entries.each_with_index
      .sort_by { |(_picture, position), index| [position.present? ? 0 : 1, position || index, index] }
      .map { |(picture, _position), _index| picture }
  end

  def attached_photos_loaded?
    association(:photos_attachments).loaded?
  end

  def attached_photos_for_display
    return photos_attachments.to_a if attached_photos_loaded?
    return [] unless photos.attached?

    photos.includes(:blob).to_a
  end

  def picture_hidden_from_site?(picture)
    ActiveModel::Type::Boolean.new.cast(picture.try(:[], "site_hidden") || picture.try(:[], :site_hidden))
  end

  def picture_url_for_visibility(picture)
    picture.try(:[], "url") || picture.try(:[], :url) || picture.try(:[], "src") || picture.try(:[], :src) || picture.try(:[], "link") || picture.try(:[], :link)
  end

  def sync_intake_answers
    self.aceita_permuta_flag = aceita_permuta_answer == "sim" if aceita_permuta_answer.present?
    self.salute_rental_management_flag = salute_rental_management_answer == "sim" if salute_rental_management_answer.present?
  end

  # Dynamic Field Setters (Array handling)
  def meta_keywords=(value)
    if value.is_a?(Array)
      super(value.reject(&:blank?).join(','))
    else
      super
    end
  end

  def caracteristicas=(value)
    if value.is_a?(Array)
      hash = AttributeOptions::HabitationFeatureNormalizer
             .normalize_list(value, category: "feature")
             .index_by(&:itself)
      super(hash)
    else
      super
    end
  end

  def infra_estrutura=(value)
    if value.is_a?(Array)
      super(AttributeOptions::HabitationFeatureNormalizer.normalize_list(value, category: "infrastructure"))
    else
      super
    end
  end

  def endereco
    address&.logradouro.presence || self[:endereco]
  end

  def unique_features
    raw = self[:caracteristica_unica]
    Array(raw).flatten.compact.map { |feature| feature.to_s.strip }.reject(&:blank?)
  end

  def effective_constructor
    constructor || empreendimento&.constructor
  end

  def constructor_name
    effective_constructor&.name.presence || construtora.presence
  end
  
  # Verifica se é um empreendimento
  def empreendimento?
    tipo == 'Empreendimento'
  end

  def standalone_category_without_development_name?
    self.class.standalone_category_without_development_name?(categoria)
  end

  def dwv_property?
    imovel_dwv.to_s.strip.casecmp("sim").zero?
  end

  def dwv_owner_user
    return unless dwv_property?

    @dwv_owner_user ||= Dwv::OwnerResolver.call(tenant)
  end

  def publicly_viewable?
    return false unless exibir_no_site_flag?
    return false unless PUBLIC_STATUSES.include?(status)
    return true if empreendimento?

    has_public_photo? && has_public_price?
  end

  def delivery_date_visible?(today = Date.current)
    data_entrega.present? && data_entrega >= today
  end

  def ready_to_move?
    readiness_values = [situacao, estado_conservacao, unique_features]

    if caracteristicas.is_a?(Hash)
      readiness_values << caracteristicas.select { |_key, value| ActiveModel::Type::Boolean.new.cast(value) }.keys
      readiness_values << caracteristicas.values
    end

    if infra_estrutura.is_a?(Array)
      readiness_values << infra_estrutura
    end

    readiness_values.flatten.compact.any? do |value|
      value.to_s.parameterize.include?("pronto")
    end
  end

  def public_unavailable_reason
    return "exibir_no_site_flag=false" unless exibir_no_site_flag?
    return "status=#{status.inspect}" unless PUBLIC_STATUSES.include?(status)
    return nil if empreendimento?
    return "sem fotos" unless has_public_photo?
    return "sem preco" unless has_public_price?

    nil
  end
  
  # Verifica se é uma unidade de empreendimento
  def unidade?
    codigo_empreendimento.present?
  end
  
  # Retorna todas as unidades disponíveis deste empreendimento
  # Empreendimento tem 'codigo', unidades têm 'codigo_empreendimento'
  def development_units
    return Habitation.none unless empreendimento? && codigo.present?
    tenant.habitations.active.where(codigo_empreendimento: codigo)
  end
  
  # Conta quantas unidades disponíveis esse empreendimento tem
  def available_units_count
    return 0 unless empreendimento?
    development_units.count
  end
  
  # Verifica se é um empreendimento com unidades
  def has_available_units?
    empreendimento? && available_units_count > 0
  end

  # --- Helpers para o card público ---
  # Para empreendimentos, agregam min..max das unidades disponíveis.
  # Para imóveis avulsos/unidades, retornam o valor próprio.

  def card_dormitorios_text
    if empreendimento?
      values = development_units.where("dormitorios_qtd > 0").pluck(:dormitorios_qtd).compact.uniq.sort
      return nil if values.empty?
      values.size == 1 ? values.first.to_s : "#{values.min} a #{values.max}"
    else
      dormitorios_qtd.to_i.positive? ? dormitorios_qtd.to_s : nil
    end
  end

  def card_vagas_text
    if empreendimento?
      values = development_units.where("vagas_qtd > 0").pluck(:vagas_qtd).compact.uniq.sort
      return nil if values.empty?
      values.size == 1 ? values.first.to_s : "#{values.min} a #{values.max}"
    else
      vagas_qtd.to_i.positive? ? vagas_qtd.to_s : nil
    end
  end

  def card_suites_text
    if empreendimento?
      values = development_units.where("suites_qtd > 0").pluck(:suites_qtd).compact.uniq.sort
      return nil if values.empty?
      values.size == 1 ? values.first.to_s : "#{values.min} a #{values.max}"
    else
      suites_qtd.to_i.positive? ? suites_qtd.to_s : nil
    end
  end

  def card_area_text
    if empreendimento?
      values = development_units.where("area_privativa_m2 > 0").pluck(:area_privativa_m2).compact
      return nil if values.empty?
      min = values.min.to_i
      max = values.max.to_i
      min == max ? "#{min} m²" : "#{min} a #{max} m²"
    else
      area_privativa_m2.to_f.positive? ? "#{area_privativa_m2.to_i} m²" : nil
    end
  end

  # A metragem divulgada no site representa exclusivamente a area privativa.
  # Area total continua disponivel para operacao, filtros e integracoes.
  def public_area_m2
    area_privativa_m2.to_f.positive? ? area_privativa_m2 : nil
  end
  
  # Retorna o título para exibição
  def display_title
    titulo_anuncio.presence || default_title
  end

  # Description fallback for legacy/plain-text and rich text sources.
  def display_description
    rich_html = rich_text_descricao_web&.body&.to_s.presence
    legacy_html = read_attribute(:descricao_web).to_s.presence
    internal_text = descricao_interna.to_s.presence
    development_text = descricao_empreendimento.to_s.presence

    rich_html || legacy_html || internal_text || development_text
  end

  def property_features_for_display
    normalize_feature_values(caracteristicas, category: "feature")
  end

  def leisure_features_for_display
    normalize_feature_values(infra_estrutura, category: "infrastructure")
  end

  def public_neighborhood
    bairro_comercial.presence || bairro
  end

  def public_location_label
    [cidade, public_neighborhood].compact_blank.join(" - ")
  end
  
  # Título padrão baseado nas características
  def default_title
    parts = []
    parts << categoria if categoria.present?
    parts << "#{dormitorios_qtd} dormitórios" if dormitorios_qtd > 0
    parts << "em #{bairro}" if bairro.present?
    parts << cidade if cidade.present?
    parts.join(' ')
  end

  def title_category_terms_in_title
    title_key = normalize_title_category(titulo_anuncio)

    TITLE_CATEGORY_TERMS.select do |term|
      term_key = normalize_title_category(term)
      title_key.start_with?(term_key)
    end
  end

  def normalize_title_category(value)
    value.to_s.parameterize
  end

  # Retorna lista de badges (etiquetas) para exibição no card
  def display_badges
    badges = []
    
    # Priority 1: Caracteristica Unica (Mapped labels from Vista)
    unique_features.each do |feature|
      text = feature.upcase
      badges << {
        text: text,
        color: badge_color_for(text),
        tailwind_color: tailwind_color_for(text)
      }
    end
    
    # Priority 2: Lançamento Flag (Manual flag)
    has_lancamento_badge = unique_features.any? { |feature| I18n.transliterate(feature.downcase).include?('lancamento') }
    if lancamento_flag && !has_lancamento_badge
      badges << { 
        text: 'LANÇAMENTO', 
        color: 'success',
        tailwind_color: 'orange-500'
      }
    end
    
    # Priority 3: Destaque Web (Featured)
    if destaque_web_flag
      badges << { 
        text: 'DESTAQUE', 
        color: 'warning text-dark',
        tailwind_color: 'yellow-500'
      }
    end
    
    badges.first(2)
  end

  def tailwind_color_for(text)
    t = text.to_s.upcase
    if t.include?('PLANTA') || t.include?('CONSTRUÇÃO') || t.include?('PRÉ-LANÇAMENTO')
      'primary-600'
    elsif t.include?('LANÇAMENTO')
      'orange-500'
    elsif t.include?('DESTAQUE') || t.include?('OPORTUNIDADE')
      'yellow-500'
    elsif t.include?('PRONTO')
      'green-600'
    else
      'primary-500'
    end
  end

  def badge_color_for(text)
    t = text.to_s.upcase
    if t.include?('PLANTA') || t.include?('CONSTRUÇÃO') || t.include?('PRÉ-LANÇAMENTO')
      'primary'
    elsif t.include?('LANÇAMENTO')
      'success'
    elsif t.include?('DESTAQUE') || t.include?('OPORTUNIDADE')
      'warning text-dark'
    elsif t.include?('PRONTO')
      'info'
    else
      'secondary'
    end
  end

  private

  def validate_codigo_empreendimento?
    codigo_empreendimento.present? && (new_record? || will_save_change_to_codigo_empreendimento?)
  end

  def codigo_empreendimento_must_exist
    parent = tenant.habitations.empreendimentos.find_by(codigo: codigo_empreendimento)
    return if parent.present?

    errors.add(:codigo_empreendimento, "não corresponde a um empreendimento válido")
  end

  def key_location_notes_required_for_other
    return unless key_location == "Outro" && key_location_notes.blank?

    errors.add(:key_location_notes, "deve ser informado quando o local da chave for Outro")
  end

  def rental_guarantee_methods_must_be_valid
    invalid_options = rental_guarantee_methods - RENTAL_GUARANTEE_METHOD_OPTIONS
    return if invalid_options.blank?

    errors.add(:rental_guarantee_method, "possui opção inválida")
  end

  def codigo_empreendimento_cannot_reference_self
    return if codigo.blank? || codigo_empreendimento.blank?
    return unless codigo.to_s == codigo_empreendimento.to_s

    errors.add(:codigo_empreendimento, "não pode referenciar o próprio imóvel")
  end

  def normalize_codigo_empreendimento
    self.codigo_empreendimento = codigo_empreendimento.to_s.strip.presence
  end

  def clear_category_mismatched_slug
    self.slug = nil if slug_category_mismatch?
  end

  def clear_unlinked_standalone_development_name
    return if empreendimento?
    return if codigo_empreendimento.present?
    return unless standalone_category_without_development_name?

    self.nome_empreendimento = nil
  end

  def sync_hierarchy_data
    if empreendimento?
      self.codigo_empreendimento = nil
      return
    end

    return if codigo_empreendimento.blank?

    parent = tenant.habitations.empreendimentos.find_by(codigo: codigo_empreendimento)
    return if parent.blank?

    force_sync = new_record? || will_save_change_to_codigo_empreendimento?

    self.nome_empreendimento = parent.nome_empreendimento.presence || parent.titulo_anuncio
    self.use_development_photos_flag = true if force_sync
    assign_development_value(:constructor_id, parent.constructor_id, force: force_sync)
    assign_development_value(:proprietor_id, parent.proprietor_id, force: force_sync)
    assign_development_value(:descricao_empreendimento, development_description_for_unit(parent), force: force_sync)
    assign_development_value(:data_entrega, parent.data_entrega, force: force_sync)
    assign_development_value(:perfil_construcao, parent.perfil_construcao, force: force_sync)
    sync_address_from_development(parent, force: force_sync)
  end

  def sync_construtora_from_constructor
    self.construtora = constructor.name if constructor.present?
  end

  def assign_development_value(attribute, value, force: false)
    return if value.blank?

    self[attribute] = value if force || self[attribute].blank?
  end

  def development_description_for_unit(parent)
    parent.descricao_empreendimento.presence || parent.display_description.to_s.presence
  end

  def sync_address_from_development(parent, force: false)
    source = parent.address
    target = ensure_address

    assign_address_value(target, :tipo_endereco, source&.tipo_endereco.presence || parent.tipo_endereco, force: force)
    assign_address_value(target, :logradouro, source&.logradouro.presence || parent.endereco, force: force)
    assign_address_value(target, :numero, source&.numero.presence || parent.numero, force: force)
    assign_address_value(target, :bairro, source&.bairro.presence || parent.bairro, force: force)
    assign_address_value(target, :bairro_comercial, source&.bairro_comercial.presence || parent.bairro_comercial, force: force)
    assign_address_value(target, :cidade, source&.cidade.presence || parent.cidade, force: force)
    assign_address_value(target, :uf, source&.uf.presence || parent.uf, force: force)
    assign_address_value(target, :cep, source&.cep.presence || parent.cep, force: force)
  end

  def assign_address_value(target, attribute, value, force: false)
    return if value.blank?

    target.public_send("#{attribute}=", value) if force || target.public_send(attribute).blank?
  end

  def sync_flags_from_features
    return unless caracteristicas.is_a?(Array)
    
    self.mobiliado_flag = caracteristicas.include?('Mobiliado')
    self.sem_mobilia_flag = caracteristicas.include?('Sem Mobília')
    self.decorado_flag = caracteristicas.include?('Decorado')
    # Piscina can be 'Piscina' or 'Piscina Privativa', let's cover both for the flag if appropriate, or just the specific one.
    # Assessing based on usual logic:
    self.piscina_flag = caracteristicas.include?('Piscina Privativa') || caracteristicas.include?('Piscina')
    self.varanda_gourmet_flag = caracteristicas.include?('Varanda Gourmet')
    self.garden_flag = caracteristicas.include?('Garden')
    self.quadra_mar_flag = caracteristicas.include?('Quadra Mar')
    self.frente_mar_avenida_atlantica_flag = caracteristicas.include?('Frente Mar')
    # Vista mar usually maps to vista mar
    self.vista_frente_mar_flag = caracteristicas.include?('Vista Mar') || caracteristicas.include?('Vista para o Mar')
    self.aceita_financiamento_flag = caracteristicas.include?('Aceita Financiamento')
    self.aceita_permuta_flag = caracteristicas.include?('Aceita Permuta')
    self.lavabo_flag = caracteristicas.include?('Lavabo')
  end

  def sanitize_fields
    fields_to_sanitize = [
      :categoria, :status, :situacao,
      :nome_empreendimento,
      :proprietario, :proprietario_email,
      :ocupacao_status, :estado_conservacao, :topografia, :foto_classificacao, :rental_guarantee_method,
      :numero_box, :dimensoes_terreno, :podcast_url,
      :matricula_imovel, :zona, :responsavel_reserva, :zelador_nome, :zelador_telefone, :regiao_foco,
      :construtora, :tipo_fachada,
      :tipo_veiculo_aceito_permuta, :permuta_localizacao, :permuta_outros_descricao
    ]
    
    fields_to_sanitize.each do |field|
      val = send(field)
      if val.is_a?(String)
        # Convert to nil if blank, just a dot, or just whitespace
        if val.blank? || val.strip == '.'
          send("#{field}=", nil)
        else
          send("#{field}=", val.strip)
        end
      end
    end
  end

  def clear_motivo_suspensao_unless_suspended
    return if self.class.normalize_status(status) == "Suspenso"

    self.motivo_suspensao = nil
  end

  def inactive_commercial_status_details_required
    case inactive_status_key
    when "suspenso"
      errors.add(:motivo_suspensao, "deve ser informado quando o status estiver Suspenso") if motivo_suspensao.blank?
    when "alugado"
      if valor_alugado_terceiros_cents.to_i <= 0
        errors.add(:valor_alugado_terceiros_cents, "deve ser informado quando o status estiver Alugado")
      end
    when "vendido"
      if valor_vendido_terceiros_cents.to_i <= 0
        errors.add(:valor_vendido_terceiros_cents, "deve ser informado quando o status estiver Vendido")
      end
    end
  end

  def unpublish_when_commercial_status_inactive
    return unless inactive_commercial_status?

    self.exibir_no_site_flag = false
    portal_publication_attribute_names.each do |attribute|
      public_send("#{attribute}=", false) if respond_to?("#{attribute}=")
    end
  end

  def inactive_status_key
    normalized_status = self.class.normalize_status(status).to_s.parameterize
    INACTIVE_STATUS_KEYWORDS.find { |keyword| normalized_status.include?(keyword) }
  end

  def portal_publication_attribute_names
    portal_columns = self.class::PORTAL_PUBLICATION_FIELDS.values
    dynamic_columns = self.class.column_names.grep(/\Apublicar_/).map(&:to_sym)

    (portal_columns + dynamic_columns).uniq
  end

  def assign_codigo_automaticamente
    return if codigo.present?

    self.codigo = broker_intake? ? self.class.next_temporary_codigo : self.class.next_automatic_codigo
  end

  def slug_candidates
    if empreendimento?
      return [
        :development_slug_base,
        [:development_slug_base, :codigo]
      ]
    end

    [
      [:tipo_imovel_slug, :cidade_slug, :bairro_slug, :codigo],
      [:tipo_imovel_slug, :cidade_slug, :codigo],
      [:categoria, :codigo]
    ]
  end

  def should_generate_new_friendly_id?
    slug.blank? ||
      (broker_intake? && will_save_change_to_codigo? && !temporary_codigo?) ||
      (empreendimento? && will_save_change_to_nome_empreendimento?) ||
      slug_category_mismatch?
  end

  def slug_category_mismatch?
    return false if empreendimento?
    return false if slug.blank? || categoria.blank? || codigo.blank?

    current_slug = slug.to_s
    code_suffix = codigo.to_s.parameterize
    expected_prefix = tipo_imovel_slug.to_s
    return false if code_suffix.blank? || expected_prefix.blank?
    return false unless current_slug.end_with?("-#{code_suffix}")

    !current_slug.start_with?("#{expected_prefix}-")
  end
  
  # Métodos auxiliares para o slug
  def development_slug_base
    nome_empreendimento.presence || titulo_anuncio.presence || default_title
  end

  def tipo_imovel_slug
    categoria&.parameterize
  end
  
  def cidade_slug
    (address&.cidade.presence || self[:cidade])&.parameterize
  end
  
  def bairro_slug
    (address&.bairro.presence || self[:bairro])&.parameterize
  end
  
  private

  def skip_auto_audit?
    ActiveModel::Type::Boolean.new.cast(skip_auto_audit)
  end

  def record_auto_audit_create
    build_auto_audit_recorder.record_create!
  end

  def record_auto_audit_update
    build_auto_audit_recorder.record_update!
  end

  def dispatch_interest_price_drop
    return unless saved_change_to_valor_venda_cents? || saved_change_to_valor_locacao_cents?

    InterestIntelligence::PropertyChangeDispatcher.price_drop(self)
  end

  def capture_auto_audit_destroy_snapshot
    self.auto_audit_destroy_snapshot = Habitations::AuditChangeRecorder.snapshot_for(self)
  end

  def record_auto_audit_destroy
    build_auto_audit_recorder(before_snapshot: auto_audit_destroy_snapshot).record_destroy!
  end

  def build_auto_audit_recorder(before_snapshot: nil)
    Habitations::AuditChangeRecorder.new(
      self,
      actor: Current.admin_user,
      source: auto_audit_source,
      before_snapshot: before_snapshot,
      metadata: { auto_recorded: true }
    )
  end

  def auto_audit_source
    return "captacao" if broker_intake?
    return "admin" if Current.admin_user.present?

    "integracao"
  end

  def has_public_photo?
    public_image_sources.any?
  end

  def has_public_price?
    valor_venda_cents.to_i.positive? || valor_locacao_cents.to_i.positive?
  end

  def set_data_cadastro_crm
    return if broker_intake?

    self.data_cadastro_crm ||= Time.current
  end

  def capture_price_reductions
    capture_sale_price_reduction
    capture_rent_price_reduction
  end

  # Marca quando o preço (venda ou locação) foi alterado, para o card exibir
  # "Preço atualizado há X dias". Só em updates — no cadastro inicial não faz
  # sentido "atualização". Guardado por has_attribute? para tolerar boot antes
  # da migration em ambientes que ainda não migraram.
  def stamp_preco_atualizado_em
    return unless has_attribute?(:preco_atualizado_em)
    return unless will_save_change_to_valor_venda_cents? || will_save_change_to_valor_locacao_cents?

    self.preco_atualizado_em = Time.current
  end

  def capture_sale_price_reduction
    return unless will_save_change_to_valor_venda_cents?
    # Respeita quem já definiu o "anterior" explicitamente (ex.: import do Vista).
    return if will_save_change_to_valor_venda_anterior_cents?

    old_cents, new_cents = attribute_change_to_be_saved(:valor_venda_cents).map(&:to_i)

    if old_cents.positive? && new_cents.positive? && new_cents < old_cents
      self.valor_venda_anterior_cents = old_cents
      self.valor_promocional_cents = new_cents unless will_save_change_to_valor_promocional_cents?
    elsif new_cents > old_cents
      # Preço subiu: deixa de ser promoção de venda — limpa "anterior" e o
      # valor promocional (que fica visível no site) para não exibir dado velho.
      self.valor_venda_anterior_cents = nil
      clear_shared_promocional_for(:sale)
    end
  end

  def capture_rent_price_reduction
    return unless will_save_change_to_valor_locacao_cents?
    return if will_save_change_to_valor_locacao_anterior_cents?

    old_cents, new_cents = attribute_change_to_be_saved(:valor_locacao_cents).map(&:to_i)

    if old_cents.positive? && new_cents.positive? && new_cents < old_cents
      self.valor_locacao_anterior_cents = old_cents
      self.valor_promocional_cents = new_cents unless will_save_change_to_valor_promocional_cents?
    elsif new_cents > old_cents
      self.valor_locacao_anterior_cents = nil
      clear_shared_promocional_for(:rent)
    end
  end

  # valor_promocional_cents é compartilhado entre venda e locação; ao subir o
  # preço de uma modalidade só limpa o promocional se a outra também não estiver
  # em desconto e se ninguém o setou explicitamente nesta gravação.
  def clear_shared_promocional_for(modality)
    return if will_save_change_to_valor_promocional_cents?

    other_discount = modality == :sale ? rent_discount? : sale_discount?
    self.valor_promocional_cents = nil unless other_discount
  end
  
  def clear_cache
    Rails.cache.delete(cache_key)
    Rails.cache.delete([self.class.name, id])
    Rails.cache.delete("habitation_#{id}")
    self.class.clear_public_filter_cache_for_tenant(tenant_id)
    
    # Limpar cache da view materializada se for um imóvel em destaque
    if destaque_web_flag_changed? || exibir_no_site_flag_changed?
      refresh_materialized_view
    end
  end
  
  def refresh_materialized_view
    # Atualizar a materialized view em background
    RefreshFeaturedPropertiesJob.perform_later if defined?(RefreshFeaturedPropertiesJob)
  end

  def normalize_feature_values(source, category: "feature")
    case source
    when Array
      source
    when Hash
      normalize_hash_features(source)
    else
      []
    end
      .map { |item| item.to_s.strip }
      .reject { |item| item.blank? || item == "." }
      .then { |items| AttributeOptions::HabitationFeatureNormalizer.normalize_list(items, category: category) }
  end

  def normalize_captacao_list(source, category: "feature")
    case source
    when String
      source.split(",")
    else
      normalize_feature_values(source, category: category)
    end
      .map { |item| item.to_s.strip }
      .reject(&:blank?)
      .uniq
  end

  def normalize_hash_features(source)
    values = source.values
    boolean_like_hash = values.all? { |value| boolean_like_value?(value) }

    if boolean_like_hash
      source.select { |_key, value| truthy_value?(value) }.keys
    else
      source.map { |key, value| value.to_s.strip.presence || key.to_s.strip }
    end
  end

  def boolean_like_value?(value)
    [true, false, nil, 0, 1, "0", "1", "true", "false", "t", "f"].include?(value)
  end

  def truthy_value?(value)
    [true, 1, "1", "true", "t"].include?(value)
  end
end
