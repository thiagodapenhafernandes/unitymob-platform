class NotificationTemplateSetting < ApplicationRecord
  include TenantScoped

  CHANNELS = {
    "whatsapp" => "WhatsApp"
  }.freeze

  PURPOSES = {
    "lead_distribution_broker" => {
      label: "Notificar corretor pela regra de distribuição",
      description: "Usado quando uma regra de distribuição envia WhatsApp para o corretor responsável.",
      default_variable_mapping: {
        "1" => "lead_name",
        "2" => "lead_origin",
        "3" => "lead_name",
        "4" => "lead_phone_or_link",
        "5" => "lead_email_or_link",
        "6" => "lead_other_or_link"
      },
      variables: {
        "lead_name" => "Nome do lead",
        "lead_origin" => "Origem do lead",
        "lead_phone_or_link" => "Telefone do lead ou link seguro",
        "lead_email_or_link" => "Email do lead ou link seguro",
        "lead_other_or_link" => "Produto/origem ou link seguro",
        "broker_name" => "Nome do corretor",
        "broker_phone" => "Telefone do corretor",
        "broker_email" => "Email do corretor"
      }
    }
  }.freeze

  belongs_to :whatsapp_template, optional: true

  before_validation :apply_default_variable_mapping

  validates :channel, presence: true, inclusion: { in: CHANNELS.keys }
  validates :purpose, presence: true, inclusion: { in: PURPOSES.keys }
  validates :purpose, uniqueness: { scope: [:tenant_id, :channel] }
  validates :whatsapp_template, presence: true, if: :whatsapp?
  validate :whatsapp_template_belongs_to_tenant
  validate :whatsapp_template_is_approved
  validate :variable_mapping_matches_template

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:channel, :purpose) }

  def self.purpose_options
    PURPOSES.map { |key, config| [config.fetch(:label), key] }
  end

  def self.template_for(tenant:, channel: "whatsapp", purpose:)
    setting_for(tenant: tenant, channel: channel, purpose: purpose)&.whatsapp_template
  end

  def self.setting_for(tenant:, channel: "whatsapp", purpose:)
    tenant.notification_template_settings
          .active
          .includes(:whatsapp_template)
          .find_by(channel: channel, purpose: purpose)
  end

  def purpose_label
    purpose_config.fetch(:label)
  end

  def purpose_description
    purpose_config.fetch(:description)
  end

  def variable_source_options
    purpose_config.fetch(:variables, {}).map { |key, label| [label, key] }
  end

  def default_variable_mapping
    purpose_config.fetch(:default_variable_mapping, {})
  end

  def variable_mapping
    metadata.fetch("variable_mapping", {}).to_h
  end

  def variable_mapping=(value)
    normalized = value.to_h.transform_keys(&:to_s).transform_values(&:to_s).select { |key, source| key.present? && source.present? }
    self.metadata = metadata.to_h.merge("variable_mapping" => normalized)
  end

  def whatsapp?
    channel == "whatsapp"
  end

  private

  def purpose_config
    PURPOSES.fetch(purpose.to_s, {})
  end

  def whatsapp_template_belongs_to_tenant
    return unless whatsapp_template && tenant

    errors.add(:whatsapp_template, "não pertence a esta conta") if whatsapp_template.tenant_id != tenant_id
  end

  def whatsapp_template_is_approved
    return unless whatsapp_template

    errors.add(:whatsapp_template, "precisa estar aprovado") unless whatsapp_template.approved?
  end

  def variable_mapping_matches_template
    return unless whatsapp_template

    count = whatsapp_template.variable_count
    return if count.zero?

    allowed_sources = purpose_config.fetch(:variables, {}).keys
    mapping = variable_mapping

    (1..count).each do |index|
      source = mapping[index.to_s]
      if source.blank?
        errors.add(:metadata, "precisa mapear a variável {{#{index}}}")
      elsif !allowed_sources.include?(source)
        errors.add(:metadata, "tem fonte inválida para a variável {{#{index}}}")
      end
    end
  end

  def apply_default_variable_mapping
    return if purpose.blank?
    return if variable_mapping.present?

    self.variable_mapping = default_variable_mapping
  end
end
