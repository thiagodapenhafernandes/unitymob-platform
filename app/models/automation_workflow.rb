class AutomationWorkflow < ApplicationRecord
  include TenantScoped

  STATUSES = %w[draft active paused archived].freeze

  belongs_to :created_by, class_name: "AdminUser", optional: true
  belongs_to :active_version, class_name: "AutomationWorkflowVersion", optional: true

  has_many :versions,
           class_name: "AutomationWorkflowVersion",
           dependent: :destroy,
           inverse_of: :automation_workflow
  has_many :executions, dependent: :destroy, class_name: "AutomationExecution"

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(updated_at: :desc) }
  scope :active, -> { where(status: "active") }

  def draft_version
    versions.where(status: "draft").order(version_number: :desc).first
  end

  def draft_version!
    current_draft = draft_version
    return reseed_stale_default_draft!(current_draft) if stale_default_draft?(current_draft)
    return current_draft if current_draft

    versions.create!(
      version_number: next_version_number,
      status: "draft",
      definition: draft_seed_definition
    )
  end

  def next_version_number
    versions.maximum(:version_number).to_i + 1
  end

  def publish!(version:, admin_user: nil)
    raise ArgumentError, "versao nao pertence ao fluxo" if version.automation_workflow_id != id

    messages = version.validation_messages(mode: :publish)
    if messages.any?
      version.record_publish_validation_errors!(messages)
      raise ActiveRecord::RecordInvalid, version
    end

    transaction do
      version.publish!(admin_user: admin_user, validate: false)
      update!(
        status: "active",
        active_version: version,
        last_activated_at: Time.current
      )
    end
  end

  def status_label
    {
      "draft" => "Rascunho",
      "active" => "Ativo",
      "paused" => "Pausado",
      "archived" => "Arquivado"
    }[status] || status
  end

  def whatsapp_campaign_source_id
    active_version&.definition_hash&.dig(:source, :whatsapp_campaign_id).presence ||
      draft_version&.definition_hash&.dig(:source, :whatsapp_campaign_id).presence
  end

  def whatsapp_campaign_source?
    whatsapp_campaign_source_id.present?
  end

  def whatsapp_campaign_managed?
    sources = whatsapp_campaign_source_metadata_list
    return false if sources.blank?
    return false if sources.any? { |source| whatsapp_campaign_customized_source?(source) }

    source = sources.first
    managed_value = source.key?(:managed_by_campaign) ? source[:managed_by_campaign] : true
    ActiveModel::Type::Boolean.new.cast(managed_value) &&
      !ActiveModel::Type::Boolean.new.cast(source[:customized_by_advanced_user])
  end

  def whatsapp_campaign_customized?
    whatsapp_campaign_source_metadata_list.any? { |source| whatsapp_campaign_customized_source?(source) }
  end

  def active?
    status == "active"
  end

  private

  def whatsapp_campaign_source_metadata_list
    [draft_version, active_version].filter_map do |version|
      source = version&.definition_hash&.dig(:source)
      next if source.blank?

      metadata = source.with_indifferent_access
      metadata if metadata[:kind].to_s == "whatsapp_campaign" || metadata[:whatsapp_campaign_id].present?
    end
  end

  def whatsapp_campaign_customized_source?(source)
    ActiveModel::Type::Boolean.new.cast(source[:customized_by_advanced_user]) ||
      source[:sync_mode].to_s == "advanced_custom"
  end

  def draft_seed_definition
    active_version&.definition_hash&.deep_dup.presence || Automation::WorkflowDefinition.default_definition
  end

  def reseed_stale_default_draft!(version)
    version.update!(definition: draft_seed_definition)
    version
  end

  def stale_default_draft?(version)
    return false unless version && active_version&.published_at
    return false if version.updated_at.to_i != version.created_at.to_i
    return false if version.created_at < active_version.published_at

    normalized_definition(version.definition_hash) == normalized_definition(Automation::WorkflowDefinition.default_definition)
  end

  def normalized_definition(definition)
    JSON.parse(definition.to_json)
  end
end
