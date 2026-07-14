class PropertyReviewPolicy < ApplicationRecord
  REGISTRATION_TYPES = {
    "apartamentos" => "Apartamentos",
    "comerciais_industriais" => "Comerciais e industriais",
    "imoveis_residenciais" => "Imóveis residenciais",
    "terrenos" => "Terrenos",
    "ficha_interna" => "Ficha interna",
    "cadastro_direto" => "Cadastro direto"
  }.freeze

  MODALITIES = {
    "venda" => "Venda",
    "locacao_anual" => "Locação anual",
    "ambos" => "Venda e locação",
    "locacao_diaria" => "Locação diária"
  }.freeze

  CATEGORIES_BY_REGISTRATION_TYPE = {
    "apartamentos" => ["Apartamento", "Cobertura", "Loft", "Studio"],
    "comerciais_industriais" => ["Sala Comercial", "Loja", "Prédio Comercial", "Galpão", "Galpão Industrial", "Área", "Casa comercial", "Condomínio Industrial", "Ponto Comercial", "Salas/Conjuntos"],
    "imoveis_residenciais" => ["Casa", "Casa em Condomínio", "Sobrado", "Rural", "Condomínio", "Chácara", "Sítio"],
    "terrenos" => ["Terreno", "Terreno em Condomínio", "Área", "Terreno Comercial", "Terreno Industrial"],
    "ficha_interna" => Habitation::CATEGORIES,
    "cadastro_direto" => Habitation::CATEGORIES
  }.freeze

  belongs_to :tenant
  belongs_to :property_setting

  before_validation :normalize_context!
  before_validation :initialize_defaults!

  validates :registration_type, presence: true, inclusion: { in: REGISTRATION_TYPES.keys }
  validates :modality, inclusion: { in: MODALITIES.keys }, allow_blank: true
  validate :validate_required_checks
  validate :validate_returnable_sections
  validate :validate_review_notification_emails

  scope :active, -> { where(active: true) }

  def self.registration_label(value)
    REGISTRATION_TYPES[value.to_s] || value.to_s.humanize
  end

  def self.modality_label(value)
    MODALITIES[value.to_s] || value.to_s.humanize
  end

  def self.registration_type_for_habitation(habitation)
    return "cadastro_direto" unless habitation&.broker_intake?
    return "ficha_interna" if habitation.intake_internal?

    registration_type_for_category(habitation.categoria)
  end

  def self.registration_type_for_category(category)
    normalized = category.to_s.parameterize
    return "terrenos" if normalized.include?("terreno") || normalized == "area"
    return "comerciais_industriais" if normalized.match?(/sala|loja|comercial|predio|galpao|ponto|conjunto/)
    return "imoveis_residenciais" if normalized.match?(/casa|sobrado|rural|chacara|sitio/)

    "apartamentos"
  end

  def active_broker_capture_checks
    PropertySetting.normalize_intake_checks(required_broker_intake_checks).presence ||
      PropertySetting.default_broker_capture_checks
  end

  def active_returnable_intake_edit_sections
    normalized_values(returnable_intake_edit_sections, PropertySetting.default_returnable_sections)
  end

  def available_returnable_field_names
    active_returnable_intake_edit_sections
      .filter_map { |section| PropertySetting::RETURNABLE_INTAKE_EDIT_SECTION_FIELDS[section.to_s] }
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

  private

  def normalize_context!
    self.registration_type = registration_type.to_s.strip.presence
    self.category = category.to_s.strip.presence
    self.modality = modality.to_s.strip.presence
  end

  def initialize_defaults!
    self.property_setting ||= PropertySetting.instance(tenant: tenant) if tenant
    return unless property_setting

    self.required_broker_intake_checks = property_setting.active_broker_capture_checks if required_broker_intake_checks.blank?
    self.returnable_intake_edit_sections = property_setting.active_returnable_intake_edit_sections if returnable_intake_edit_sections.blank?
    self.required_broker_intake_checks = PropertySetting.normalize_intake_checks(required_broker_intake_checks).presence ||
                                         property_setting.active_broker_capture_checks
    self.returnable_intake_edit_sections = normalized_values(
      returnable_intake_edit_sections,
      property_setting.active_returnable_intake_edit_sections
    )
    self.broker_capture_layer_enabled = property_setting.broker_capture_layer_enabled if broker_capture_layer_enabled.nil?
    self.notify_internal_review_events = property_setting.notify_internal_review_events if notify_internal_review_events.nil?
    self.notify_email_review_events = property_setting.notify_email_review_events if notify_email_review_events.nil?
    self.review_notification_emails = property_setting.review_notification_emails if review_notification_emails.nil?
  end

  def validate_required_checks
    invalid = Array(required_broker_intake_checks).map(&:to_s).reject do |check|
      PropertySetting::BROKER_INTAKE_CHECK_OPTIONS.key?(check)
    end

    errors.add(:required_broker_intake_checks, "contém validações inválidas: #{invalid.join(', ')}") if invalid.any?
  end

  def validate_returnable_sections
    invalid = Array(returnable_intake_edit_sections).map(&:to_s).reject do |section|
      PropertySetting::RETURNABLE_INTAKE_EDIT_SECTION_OPTIONS.key?(section)
    end

    errors.add(:returnable_intake_edit_sections, "contém seções inválidas: #{invalid.join(', ')}") if invalid.any?
  end

  def validate_review_notification_emails
    return if review_notification_emails.blank?

    invalid_emails = review_notification_email_addresses.reject do |email|
      URI::MailTo::EMAIL_REGEXP.match?(email)
    end

    errors.add(:review_notification_emails, "contém e-mails inválidos: #{invalid_emails.join(', ')}") if invalid_emails.any?
  end

  def normalized_values(values, default_values)
    checks = Array(values).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    checks.presence || default_values
  end
end
