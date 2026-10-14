class AutomationWorkflowVersion < ApplicationRecord
  include TenantScoped

  STATUSES = %w[draft published archived].freeze

  belongs_to :automation_workflow, inverse_of: :versions
  belongs_to :created_by, class_name: "AdminUser", optional: true
  belongs_to :published_by, class_name: "AdminUser", optional: true

  has_many :executions,
           class_name: "AutomationExecution",
           dependent: :restrict_with_error,
           inverse_of: :automation_workflow_version

  before_validation :set_defaults
  after_update_commit :enqueue_existing_leads!, if: -> { saved_change_to_status? && status == "published" }

  validates :version_number, numericality: { only_integer: true, greater_than: 0 }
  validates :version_number, uniqueness: { scope: :automation_workflow_id }
  validates :status, inclusion: { in: STATUSES }
  validate :definition_must_be_valid

  scope :draft, -> { where(status: "draft") }
  scope :published, -> { where(status: "published") }

  def definition_hash
    definition.is_a?(Hash) ? definition.with_indifferent_access : {}
  end

  def validation_messages(mode: :draft)
    Automation::WorkflowDefinition.validate(definition_hash, mode: mode)
  end

  def publish!(admin_user: nil, validate: true)
    if validate
      messages = validation_messages(mode: :publish)
      if messages.any?
        record_publish_validation_errors!(messages)
        raise ActiveRecord::RecordInvalid, self
      end
    end

    transaction do
      automation_workflow.versions.published.where.not(id: id).update_all(status: "archived", updated_at: Time.current)
      update!(
        status: "published",
        published_by: admin_user,
        published_at: Time.current,
        validation_snapshot: { "errors" => [] }
      )
    end
  end

  def record_publish_validation_errors!(messages)
    messages.each { |message| errors.add(:definition, message) }
    self.validation_snapshot = { "errors" => messages }
    update_column(:validation_snapshot, validation_snapshot) if persisted?
  end

  def enqueue_existing_leads!
    entry = Array(definition_hash[:nodes]).find { |node| node[:type].to_s == "entry" }
    return unless entry&.dig(:config, :entry_policy).to_s == "existing_and_future"

    Automation::BackfillWorkflowJob.perform_later(automation_workflow_id, id)
  end

  private

  def set_defaults
    self.definition = Automation::WorkflowDefinition.default_definition if definition.blank?
    self.version_number ||= automation_workflow&.next_version_number || 1
  end

  def definition_must_be_valid
    validation_messages.each { |message| errors.add(:definition, message) }
  end
end
