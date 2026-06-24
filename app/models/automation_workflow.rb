class AutomationWorkflow < ApplicationRecord
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

  def active?
    status == "active"
  end

  private

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
