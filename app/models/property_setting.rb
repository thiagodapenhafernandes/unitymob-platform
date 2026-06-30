class PropertySetting < ApplicationRecord
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
    "situacao" => "Situação",
    "ocupacao" => "Ocupação",
    "caracteristicas" => "Mais características",
    "infraestrutura" => "Infraestrutura & lazer",
    "valor_negociacao" => "Valor de venda / locação",
    "financeiro" => "Condomínio e IPTU",
    "condicoes_negociacao" => "Condições de negociação",
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
    "caracteristicas" => %w[area vagas situacao ocupacao caracteristicas],
    "infraestrutura" => %w[infraestrutura],
    "negociacao" => %w[valor_negociacao financeiro condicoes_negociacao],
    "fotos" => %w[fotos autorizacao],
    "visitas" => %w[chaves visitas],
    "complemento" => %w[definicoes titulo titulo_categoria descricao]
  }.freeze

  # Chaves que só existem no formato legado (sem equivalente granular de mesmo nome).
  # Servem como marcador inequívoco de que um conjunto ainda está no formato antigo.
  LEGACY_ONLY_BROKER_INTAKE_KEYS = %w[negociacao complemento].freeze

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

  def self.instance
    setting = first_or_initialize(watermark_position: "bottom_left")
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
  end

  def self.default_watermark_size_for(position)
    position == "center" ? CENTER_WATERMARK_SIZE_PERCENTAGE : DEFAULT_WATERMARK_SIZE_PERCENTAGE
  end

  def watermark_configured?
    watermark_image.attached?
  end

  private

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
