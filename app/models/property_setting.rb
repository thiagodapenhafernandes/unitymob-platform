class PropertySetting < ApplicationRecord
  AI_PROPERTY_SEARCH_DATA_SOURCES = %w[database external_api imported_xml json_feed].freeze
  AI_PROPERTY_SEARCH_SORTS = %w[relevance price_asc price_desc recent area_desc].freeze
  AI_PROPERTY_SEARCH_FIELD_OPTIONS = {
    "transaction_type" => "Finalidade (venda ou locação)",
    "property_type" => "Tipo do imóvel",
    "city" => "Cidade",
    "neighborhood" => "Bairro",
    "development" => "Empreendimento (nome e aliases)",
    "developer_name" => "Incorporadora / construtora",
    "property_condition" => "Condição (lançamento)",
    "bedrooms" => "Quartos",
    "suites" => "Suítes",
    "bathrooms" => "Banheiros",
    "parking_spaces" => "Vagas",
    "private_area" => "Área privativa",
    "total_area" => "Área total",
    "price" => "Preço",
    "condominium_fee" => "Condomínio",
    "property_tax" => "IPTU",
    "amenities" => "Características e lazer",
    "property_code" => "Código do imóvel"
  }.freeze
  AI_PROPERTY_SEARCH_RESULT_FIELD_OPTIONS = {
    "cover_image" => "Foto de capa",
    "property_code" => "Código",
    "title" => "Título",
    "neighborhood" => "Bairro",
    "city" => "Cidade",
    "price" => "Preço",
    "bedrooms" => "Quartos",
    "suites" => "Suítes",
    "parking_spaces" => "Vagas",
    "private_area" => "Área privativa",
    "development_name" => "Empreendimento"
  }.freeze
  AI_PROPERTY_SEARCH_PROFILE_OPTIONS = {
    "account_owner" => "Responsável pela conta",
    "custom_profile" => "Perfis personalizados",
    "agent" => "Corretores"
  }.freeze
  DEFAULT_AI_PROPERTY_SEARCH_INSTRUCTIONS = <<~TEXT.strip.freeze
    Interprete a solicitação exclusivamente como uma busca de imóveis.
    Use o JSON de contexto do catálogo enviado pelo backend como referência indireta e segura para reconhecer nomes, bairros, cidades, empreendimentos, incorporadoras e características disponíveis no tenant.
    Extraia apenas filtros compatíveis com os campos autorizados.
    Não invente informações, não retorne imóveis, não gere SQL e não descreva consultas.
    Quando um critério estiver ambíguo, mantenha-o vazio ou solicite esclarecimento.
    Quando houver faixa de preço, interprete sempre como intervalo real, por exemplo: "entre R$ 1,5 milhão e R$ 2 milhões" vira price_min = 1500000 e price_max = 2000000.
    Se houver current_filters, considere-os como a busca em andamento; se a fala indicar nova busca, ignore o contexto anterior.
    Retorne clarifying_question como null.
  TEXT
  DEFAULT_AI_PROPERTY_SEARCH_ALLOWED_FIELDS = AI_PROPERTY_SEARCH_FIELD_OPTIONS.keys.freeze
  DEFAULT_AI_PROPERTY_SEARCH_RESULT_FIELDS = %w[cover_image property_code title neighborhood city price bedrooms suites parking_spaces private_area development_name].freeze
  DEFAULT_AI_PROPERTY_SEARCH_ALLOWED_PROFILES = %w[account_owner custom_profile agent].freeze
  AI_PROPERTY_SEARCH_CATALOG_CONTEXT_LIMITS = {
    property_types: { default: 12, range: 1..50 },
    cities: { default: 12, range: 1..50 },
    neighborhoods: { default: 18, range: 1..80 },
    developments: { default: 12, range: 1..50 },
    feature_terms: { default: 20, range: 1..100 },
    alias_names: { default: 5, range: 1..20 }
  }.freeze
  DEFAULT_WATERMARK_SIZE_PERCENTAGE = 28
  CENTER_WATERMARK_SIZE_PERCENTAGE = 58
  DEFAULT_WATERMARK_OPACITY_PERCENTAGE = 100
  WATERMARK_SIZE_RANGE = 10..120
  WATERMARK_OPACITY_RANGE = 5..100

  WATERMARK_POSITIONS = {
    "bottom_left" => "Inferior esquerdo",
    "bottom_right" => "Inferior direito",
    "center" => "Centro"
  }.freeze

  # Validações granulares exigidas antes de enviar a captação para revisão.
  # Cada chave liga-se a uma regra específica em Habitation#intake_missing_requirements.
  BROKER_INTAKE_CHECK_OPTIONS = {
    "proprietario" => "Dados do proprietário",
    "proprietario_cidade" => "Cidade do proprietário",
    "endereco" => "Endereço e localização",
    "empreendimento" => "Empreendimento",
    "unidade" => "Número da unidade",
    "definicoes" => "Definições básicas (categoria e status)",
    "titulo" => "Título do anúncio",
    "titulo_categoria" => "Título coerente com a categoria",
    "descricao" => "Descrição do imóvel",
    "area" => "Dimensões e área",
    "vagas" => "Vaga de garagem",
    "tipo_vaga" => "Tipo de vaga",
    "box" => "Box da vaga",
    "situacao" => "Situação",
    "ocupacao" => "Ocupação",
    "caracteristicas" => "Mais características",
    "infraestrutura" => "Infraestrutura & lazer",
    "valor_negociacao" => "Valor de venda / locação",
    "financeiro" => "Condomínio e IPTU",
    "admin_locacao" => "Administração da locação",
    "garantia_locaticia" => "Garantia locatícia",
    "permuta" => "Aceita permuta",
    "parcelamento" => "Quantidade de parcelas",
    "chaves" => "Chaves",
    "visitas" => "Dias de visita",
    "fotos" => "Fotos ou agenda com fotógrafo",
    "autorizacao" => "Autorização do proprietário"
  }.freeze

  # Mapa de compatibilidade: blocos legados (8 grupos) -> validações granulares atuais.
  # Usado para migrar registros antigos sem perder a regra de negócio.
  LEGACY_BROKER_INTAKE_CHECK_MAP = {
    "proprietario" => %w[proprietario proprietario_cidade],
    "endereco" => %w[endereco empreendimento unidade],
    "caracteristicas" => %w[area vagas tipo_vaga box situacao ocupacao caracteristicas],
    "infraestrutura" => %w[infraestrutura],
    "negociacao" => %w[valor_negociacao financeiro admin_locacao garantia_locaticia permuta parcelamento],
    "condicoes_negociacao" => %w[admin_locacao garantia_locaticia permuta parcelamento],
    "fotos" => %w[fotos autorizacao],
    "visitas" => %w[chaves visitas],
    "complemento" => %w[definicoes titulo titulo_categoria descricao]
  }.freeze

  # Chaves que só existem no formato legado (sem equivalente granular de mesmo nome).
  # Servem como marcador inequívoco de que um conjunto ainda está no formato antigo.
  LEGACY_ONLY_BROKER_INTAKE_KEYS = %w[negociacao condicoes_negociacao complemento].freeze

  RETURNABLE_INTAKE_EDIT_SECTION_OPTIONS = {
    "proprietario" => "Dados do proprietário",
    "endereco" => "Endereço",
    "caracteristicas" => "Características do imóvel",
    "infraestrutura" => "Infraestrutura & lazer",
    "negociacao" => "Negociação e valores",
    "fotos" => "Fotos e autorização",
    "visitas" => "Visita e chaves"
  }.freeze

  RETURNABLE_INTAKE_EDIT_SECTION_FIELDS = {
    "proprietario" => %w[
      proprietario_nome
      proprietario_telefone
      proprietario_email
      proprietario_codigo
      proprietario_cpf_cnpj
      proprietario
      proprietario_celular
      proprietario_telefone_comercial
      proprietario_telefone_residencial
      observacoes_visitas
    ].freeze,
    "endereco" => %w[
      address_attributes
      zip_code
      street
      street_number
      neighborhood
      city
      state
      edificio_nome
      unidade_numero
      cep
      logradouro
      numero
      bairro
      cidade
      uf
    ].freeze,
    "caracteristicas" => %w[
      categoria
      status
      situacao
      ocupacao_status
      dormitorios_qtd
      suites_qtd
      banheiros_qtd
      vagas_qtd
      area_total_m2
      area_privativa_m2
      area_terreno_m2
      area_util_m2
      area_total
      area_privativa
      caracteristicas
      caracteristicas_imovel
      caracteristicas_imovel_ids
      caracteristicas_predio
      caracteristicas_predio_ids
      salao
      foto_classificacao
      chaves_com
    ].freeze,
    "infraestrutura" => %w[
      infra_estrutura
      caracteristicas_predio
      caracteristicas_predio_ids
    ].freeze,
    "negociacao" => %w[
      intake_modalidade
      valor_venda
      valor_locacao
      valor_condominio
      valor_iptu
      valor_venda_formatted
      valor_locacao_formatted
      valor_condominio_formatted
      valor_iptu_formatted
      aceita_permuta
      aceita_permuta_answer
      aceita_parcelamento
      aceita_parcelamento_flag
      numero_prestacoes
      salute_rental_management_answer
      rental_guarantee_method
      aceita_financiamento_flag
      aceita_permuta_veiculo_flag
      aceita_permuta_imovel_flag
      aceita_permuta_outros_flag
      motivo_venda
      observacoes
      condicoes_negociacao
      valor_total
      valor_total_cents
      aceita_parcelamento
    ].freeze,
    "fotos" => %w[
      photo_flow_choice
      photo_session_requested_at
      photo_session_url
      fotos
      photos
      autorizacoes_venda
      autorizacao_pdf
    ].freeze,
    "visitas" => %w[
      key_location
      skip_visitas
      dias_visitas
      observacoes_visitas
      key_location_notes
      senha_imovel
      senha_portaria
      distancia_praia
      topografia
      descricao_interna
      observacoes_visitas
      chaves_com
    ].freeze
  }.freeze

  has_one_attached :watermark_image
  belongs_to :broker_capture_fallback_admin_user, class_name: "AdminUser", optional: true

  before_validation :initialize_defaults!

  validates :watermark_position, presence: true, inclusion: { in: WATERMARK_POSITIONS.keys }
  validates :watermark_size_percentage,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: WATERMARK_SIZE_RANGE.begin,
              less_than_or_equal_to: WATERMARK_SIZE_RANGE.end
            }
  validates :watermark_opacity_percentage,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: WATERMARK_OPACITY_RANGE.begin,
              less_than_or_equal_to: WATERMARK_OPACITY_RANGE.end
            }

  validate :validate_required_checks
  validate :validate_returnable_sections
  validate :validate_fallback_admin_user
  validate :validate_review_notification_emails
  validate :validate_ai_property_search_settings

  def self.broker_intake_check_keys
    BROKER_INTAKE_CHECK_OPTIONS.keys
  end

  def self.returnable_edit_section_keys
    RETURNABLE_INTAKE_EDIT_SECTION_OPTIONS.keys
  end

  def self.default_broker_capture_checks
    BROKER_INTAKE_CHECK_OPTIONS.keys
  end

  # Expande chaves legadas para suas validações granulares; chaves desconhecidas/granulares
  # passam direto. NÃO usar com dados já no formato granular (gera duplicatas falsas em
  # chaves que existem nos dois formatos, ex.: "fotos").
  def self.expand_legacy_intake_checks(values)
    Array(values).flat_map { |value| LEGACY_BROKER_INTAKE_CHECK_MAP[value.to_s] || [value.to_s] }.uniq
  end

  # Normaliza um conjunto de validações: expande apenas quando detecta formato legado
  # (presença de chaves exclusivas do formato antigo), limpa e remove duplicatas.
  def self.normalize_intake_checks(values)
    keys = Array(values).map(&:to_s)
    keys = expand_legacy_intake_checks(keys) if (keys & LEGACY_ONLY_BROKER_INTAKE_KEYS).any?
    keys.map(&:strip).reject(&:blank?).uniq
  end

  def self.default_returnable_sections
    RETURNABLE_INTAKE_EDIT_SECTION_OPTIONS.keys
  end

  def active_broker_capture_checks
    self.class.normalize_intake_checks(required_broker_intake_checks).presence ||
      self.class.default_broker_capture_checks
  end

  def active_returnable_intake_edit_sections
    normalized_checks(returnable_intake_edit_sections, self.class.default_returnable_sections)
  end

  def available_returnable_field_names
    active_returnable_intake_edit_sections
      .filter_map { |section| RETURNABLE_INTAKE_EDIT_SECTION_FIELDS[section.to_s] }
      .flatten
      .uniq
      .reject(&:blank?)
  end

  def review_notification_email_addresses
    return [] if review_notification_emails.blank?

    review_notification_emails
      .to_s
      .split(/[,\n;]+/)
      .map { |email| email.to_s.strip }
      .reject(&:blank?)
      .uniq
  end

  def broker_capture_layer_visible_to?(admin_user)
    return true if broker_capture_layer_enabled
    return false if admin_user.blank?

    admin_user.tenant_owner? || admin_user.can?(:review, :captacoes)
  end

  def broker_capture_layer_configured?
    !broker_capture_layer_enabled || broker_capture_fallback_admin_user_id.present?
  end

  belongs_to :tenant, optional: true

  # Uma configuração POR CONTA (antes era 1 linha global — vazava entre
  # tenants). Pré-migration (sem coluna) mantém o comportamento antigo.
  def self.instance(tenant: Current.tenant)
    setting =
      if column_names.include?("tenant_id") && tenant
        where(tenant_id: tenant.id).first_or_initialize(watermark_position: "bottom_left")
      else
        first_or_initialize(watermark_position: "bottom_left")
      end
    setting.initialize_defaults!
    setting.save! if setting.new_record? || setting.changed?
    setting
  end

  def initialize_defaults!
    self.watermark_position ||= "bottom_left"
    self.watermark_size_percentage ||= self.class.default_watermark_size_for(watermark_position)
    self.watermark_opacity_percentage ||= DEFAULT_WATERMARK_OPACITY_PERCENTAGE
    self.broker_capture_layer_enabled = true if broker_capture_layer_enabled.nil?
    self.notify_internal_review_events = true if notify_internal_review_events.nil?
    self.notify_email_review_events = false if notify_email_review_events.nil?
    self.required_broker_intake_checks = self.class.default_broker_capture_checks if required_broker_intake_checks.nil?
    self.returnable_intake_edit_sections = self.class.default_returnable_sections if returnable_intake_edit_sections.nil?
    self.required_broker_intake_checks = self.class.normalize_intake_checks(required_broker_intake_checks).presence ||
                                         self.class.default_broker_capture_checks
    self.returnable_intake_edit_sections = normalized_checks(returnable_intake_edit_sections, self.class.default_returnable_sections)
    initialize_ai_property_search_defaults!
  end

  def ai_property_search_available_to?(admin_user)
    return false unless ai_property_search_enabled?
    return false if admin_user.blank? || admin_user.tenant_id != tenant_id
    return false unless admin_user.can?(:view, :imoveis)

    ai_property_search_allowed_profiles.include?(ai_property_search_profile_key(admin_user))
  end

  def ai_property_search_message(attribute, variables = {})
    format(public_send(attribute).to_s, variables.symbolize_keys)
  rescue KeyError, ArgumentError
    public_send(attribute).to_s
  end

  def ai_property_search_profile_key(admin_user)
    return "account_owner" if admin_user.tenant_owner?
    return "agent" if admin_user.profile&.key.to_s == "agent"

    "custom_profile"
  end

  def self.default_watermark_size_for(position)
    position == "center" ? CENTER_WATERMARK_SIZE_PERCENTAGE : DEFAULT_WATERMARK_SIZE_PERCENTAGE
  end

  def watermark_configured?
    watermark_image.attached?
  end

  private

  def initialize_ai_property_search_defaults!
    return unless has_attribute?(:ai_property_search_enabled)

    self.ai_property_search_data_source ||= "database"
    self.ai_property_search_default_sort ||= "relevance"
    self.ai_property_search_max_results ||= 20
    self.ai_property_search_price_tolerance_percentage ||= 10
    self.ai_property_search_allow_clarifying_questions = true if ai_property_search_allow_clarifying_questions.nil?
    self.ai_property_search_require_filter_confirmation = false if ai_property_search_require_filter_confirmation.nil?
    self.ai_property_search_max_audio_duration_seconds ||= 60
    self.ai_property_search_language ||= "pt-BR"
    self.ai_property_search_history_enabled = false if ai_property_search_history_enabled.nil?
    self.ai_property_search_history_retention_days ||= 30
    self.ai_property_search_development_name_enabled = true if ai_property_search_development_name_enabled.nil?
    self.ai_property_search_developer_name_enabled = true if ai_property_search_developer_name_enabled.nil?
    self.ai_property_search_fuzzy_matching_enabled = true if ai_property_search_fuzzy_matching_enabled.nil?
    self.ai_property_search_fuzzy_similarity_threshold ||= 0.30
    if has_attribute?(:ai_property_search_transcription_vocabulary_enabled) && ai_property_search_transcription_vocabulary_enabled.nil?
      self.ai_property_search_transcription_vocabulary_enabled = true
    end
    if has_attribute?(:ai_property_search_resilient_search_enabled) && ai_property_search_resilient_search_enabled.nil?
      self.ai_property_search_resilient_search_enabled = false
    end
    if has_attribute?(:ai_property_search_location_fuzzy_threshold)
      self.ai_property_search_location_fuzzy_threshold ||= 0.40
    end
    self.ai_property_search_development_aliases_enabled = true if ai_property_search_development_aliases_enabled.nil?
    self.ai_property_search_search_by_characteristics_enabled = true if ai_property_search_search_by_characteristics_enabled.nil?
    self.ai_property_search_sharing_enabled = true if ai_property_search_sharing_enabled.nil?
    self.ai_property_search_share_max_properties ||= 20
    self.ai_property_search_share_expiration_days ||= 30
    self.ai_property_search_visitor_recognition_days ||= 365
    self.ai_property_search_share_title ||= "Imóveis selecionados"
    self.ai_property_search_share_message ||= "Separei %{count} imóveis para você."
    self.ai_property_search_public_eyebrow ||= "Seleção preparada para você"
    self.ai_property_search_public_title ||= "%{count} imóvel(is) selecionado(s)"
    self.ai_property_search_public_description ||= "Veja os detalhes e marque os imóveis que realmente despertaram seu interesse."
    self.ai_property_search_view_property_label ||= "Ver imóvel"
    self.ai_property_search_interest_button_label ||= "Tenho interesse"
    self.ai_property_search_identity_title ||= "Como podemos identificar você?"
    self.ai_property_search_identity_description ||= "Informe uma vez. Nos próximos imóveis, seu interesse será enviado diretamente ao corretor."
    self.ai_property_search_identity_name_label ||= "Nome"
    self.ai_property_search_identity_phone_label ||= "WhatsApp"
    self.ai_property_search_identity_submit_label ||= "Enviar interesse"
    self.ai_property_search_identity_cancel_label ||= "Cancelar"
    self.ai_property_search_interest_success_message ||= "Interesse enviado ao corretor."
    self.ai_property_search_lead_origin ||= "Seleção compartilhada"
    self.ai_property_search_broker_panel_title ||= "Interesses nas suas seleções"
    self.ai_property_search_broker_event_message ||= "%{name} demonstrou interesse"
    self.ai_property_search_selection_count_message ||= "%{count} selecionado(s)"
    self.ai_property_search_share_button_label ||= "Compartilhar"
    self.ai_property_search_link_copied_message ||= "Link copiado para compartilhar."
    self.ai_property_search_share_error_message ||= "Não foi possível compartilhar."
    self.ai_property_search_interest_error_message ||= "Não foi possível registrar o interesse."
    self.ai_property_search_broker_event_meta ||= "%{count} imóvel(is) agrupado(s)"
    self.ai_property_search_sharing_disabled_message ||= "Compartilhamento de seleções desativado."
    self.ai_property_search_instructions = DEFAULT_AI_PROPERTY_SEARCH_INSTRUCTIONS if ai_property_search_instructions.blank?
    self.ai_property_search_welcome_message ||= "Descreva o imóvel que você procura, informando localização, tipo, faixa de valor, quartos, vagas ou outras características."
    self.ai_property_search_processing_message ||= "Estou interpretando sua busca e procurando os imóveis disponíveis."
    self.ai_property_search_no_results_message ||= "Não encontrei imóveis com todos esses critérios. Tente ampliar a localização, a faixa de valor ou reduzir algum requisito."
    self.ai_property_search_allowed_fields = DEFAULT_AI_PROPERTY_SEARCH_ALLOWED_FIELDS if ai_property_search_allowed_fields.blank?
    self.ai_property_search_result_fields = DEFAULT_AI_PROPERTY_SEARCH_RESULT_FIELDS if ai_property_search_result_fields.blank?
    self.ai_property_search_allowed_profiles = DEFAULT_AI_PROPERTY_SEARCH_ALLOWED_PROFILES if ai_property_search_allowed_profiles.blank?
    self.ai_property_search_allow_flexible_results = true if ai_property_search_allow_flexible_results.nil?
    self.ai_property_search_allowed_fields = Array(ai_property_search_allowed_fields).map(&:to_s).compact_blank.uniq
    self.ai_property_search_result_fields = Array(ai_property_search_result_fields).map(&:to_s).compact_blank.uniq
    self.ai_property_search_allowed_profiles = Array(ai_property_search_allowed_profiles).map(&:to_s).compact_blank.uniq
    initialize_ai_property_search_catalog_context_defaults!
  end

  public

  def ai_property_search_catalog_context_limits
    AI_PROPERTY_SEARCH_CATALOG_CONTEXT_LIMITS.transform_values do |definition|
      definition[:default]
    end.merge(
      property_types: catalog_limit_value(:property_types),
      cities: catalog_limit_value(:cities),
      neighborhoods: catalog_limit_value(:neighborhoods),
      developments: catalog_limit_value(:developments),
      feature_terms: catalog_limit_value(:feature_terms),
      alias_names: catalog_limit_value(:alias_names)
    )
  end

  private

  def validate_ai_property_search_settings
    return unless has_attribute?(:ai_property_search_enabled)

    errors.add(:ai_property_search_data_source, "é inválida") unless ai_property_search_data_source.in?(AI_PROPERTY_SEARCH_DATA_SOURCES)
    errors.add(:ai_property_search_default_sort, "é inválida") unless ai_property_search_default_sort.in?(AI_PROPERTY_SEARCH_SORTS)
    validate_ai_array(:ai_property_search_allowed_fields, AI_PROPERTY_SEARCH_FIELD_OPTIONS.keys)
    validate_ai_array(:ai_property_search_result_fields, AI_PROPERTY_SEARCH_RESULT_FIELD_OPTIONS.keys)
    validate_ai_array(:ai_property_search_allowed_profiles, AI_PROPERTY_SEARCH_PROFILE_OPTIONS.keys)
    validate_ai_range(:ai_property_search_max_results, 1..100)
    validate_ai_range(:ai_property_search_price_tolerance_percentage, 0..30)
    validate_ai_range(:ai_property_search_max_audio_duration_seconds, 5..180)
    validate_ai_range(:ai_property_search_history_retention_days, 1..365)
    validate_ai_range(:ai_property_search_share_max_properties, 1..100) if has_attribute?(:ai_property_search_share_max_properties)
    validate_ai_range(:ai_property_search_share_expiration_days, 1..365) if has_attribute?(:ai_property_search_share_expiration_days)
    validate_ai_range(:ai_property_search_visitor_recognition_days, 1..730) if has_attribute?(:ai_property_search_visitor_recognition_days)
    validate_ai_range(:ai_property_search_broker_events_limit, 1..20) if has_attribute?(:ai_property_search_broker_events_limit)
    validate_ai_catalog_context_limits if has_attribute?(:ai_property_search_catalog_property_types_limit)
    threshold = ai_property_search_fuzzy_similarity_threshold.to_f
    errors.add(:ai_property_search_fuzzy_similarity_threshold, "deve estar entre 0,10 e 1,00") unless threshold.between?(0.10, 1.0)
    if has_attribute?(:ai_property_search_location_fuzzy_threshold)
      location_threshold = ai_property_search_location_fuzzy_threshold.to_f
      errors.add(:ai_property_search_location_fuzzy_threshold, "deve estar entre 0,10 e 1,00") unless location_threshold.between?(0.10, 1.0)
    end
    errors.add(:ai_property_search_language, "não pode ficar em branco") if ai_property_search_language.blank?
  end

  def validate_ai_array(attribute, allowed)
    invalid = Array(public_send(attribute)).map(&:to_s) - allowed
    errors.add(attribute, "contém valores inválidos: #{invalid.join(', ')}") if invalid.any?
  end

  def validate_ai_range(attribute, range)
    value = public_send(attribute)
    errors.add(attribute, "deve estar entre #{range.begin} e #{range.end}") unless value.to_i.in?(range)
  end

  def initialize_ai_property_search_catalog_context_defaults!
    AI_PROPERTY_SEARCH_CATALOG_CONTEXT_LIMITS.each do |key, definition|
      attr_name = ai_catalog_limit_attribute(key)
      next unless has_attribute?(attr_name)

      public_send("#{attr_name}=", definition[:default]) if public_send(attr_name).blank?
    end
  end

  def validate_ai_catalog_context_limits
    AI_PROPERTY_SEARCH_CATALOG_CONTEXT_LIMITS.each do |key, definition|
      attr_name = ai_catalog_limit_attribute(key)
      validate_ai_range(attr_name, definition[:range]) if has_attribute?(attr_name)
    end
  end

  def ai_catalog_limit_attribute(key)
    "ai_property_search_catalog_#{key}_limit"
  end

  def catalog_limit_value(key)
    attr_name = ai_catalog_limit_attribute(key)
    return AI_PROPERTY_SEARCH_CATALOG_CONTEXT_LIMITS.fetch(key)[:default] unless has_attribute?(attr_name)

    public_send(attr_name).to_i.presence || AI_PROPERTY_SEARCH_CATALOG_CONTEXT_LIMITS.fetch(key)[:default]
  end

  def validate_required_checks
    invalid = Array(required_broker_intake_checks).map(&:to_s).reject do |check|
      BROKER_INTAKE_CHECK_OPTIONS.key?(check)
    end

    return if invalid.blank?

    errors.add(:required_broker_intake_checks, "contém validações inválidas: #{invalid.join(', ')}")
  end

  def validate_returnable_sections
    invalid = Array(returnable_intake_edit_sections).map(&:to_s).reject do |section|
      RETURNABLE_INTAKE_EDIT_SECTION_OPTIONS.key?(section)
    end

    return if invalid.blank?

    errors.add(:returnable_intake_edit_sections, "contém seções inválidas: #{invalid.join(', ')}")
  end

  def validate_fallback_admin_user
    if !broker_capture_layer_enabled && broker_capture_fallback_admin_user_id.blank?
      errors.add(:broker_capture_fallback_admin_user, "deve ser informado quando a revisão administrativa está desativada.")
      return
    end

    return if broker_capture_layer_enabled
    return if broker_capture_fallback_admin_user_id.blank?
    return if broker_capture_fallback_admin_user_eligible?

    errors.add(:broker_capture_fallback_admin_user, "deve ser um usuário administrativo")
  end

  def broker_capture_fallback_admin_user_eligible?
    user = broker_capture_fallback_admin_user
    return false if user.blank?
    return true if user.tenant_owner?

    user.can?(:review, :captacoes) && user.owns_all?(:captacoes)
  end

  def normalized_checks(values, default_values)
    checks = Array(values).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    return checks if values.present?

    valid_checks = Array(default_values).map(&:to_s)
    normalized = checks.select { |value| valid_checks.include?(value) }
    normalized.presence || default_values
  end

  def validate_review_notification_emails
    return if review_notification_emails.blank?

    invalid_emails = review_notification_email_addresses.reject do |email|
      URI::MailTo::EMAIL_REGEXP.match?(email)
    end

    return if invalid_emails.blank?

    errors.add(:review_notification_emails, "contém e-mails inválidos: #{invalid_emails.join(", ")}")
  end
end
