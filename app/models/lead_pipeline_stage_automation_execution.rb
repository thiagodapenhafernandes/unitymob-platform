class LeadPipelineStageAutomationExecution < ApplicationRecord
  include TenantScoped

  STATUSES = {
    "started" => "Iniciada",
    "succeeded" => "Concluída",
    "failed" => "Falhou"
  }.freeze

  belongs_to :lead_pipeline_stage_automation
  belongs_to :lead
  belongs_to :lead_pipeline_stage

  validates :action_type, :trigger, :stage_entered_at, :started_at, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :lead_pipeline_stage_automation_id,
            uniqueness: { scope: [:tenant_id, :lead_id, :stage_entered_at] }
  validate :records_must_belong_to_tenant

  scope :succeeded, -> { where(status: "succeeded") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }

  STATUSES.keys.each do |value|
    define_method("#{value}?") { status.to_s == value }
  end

  def succeeded!
    update!(
      status: "succeeded",
      finished_at: Time.current,
      error_class: nil,
      error_message: nil
    )
  end

  def failed!(error)
    update!(
      status: "failed",
      finished_at: Time.current,
      error_class: error.class.name,
      error_message: error.message.to_s.truncate(500)
    )
  end

  private

  def records_must_belong_to_tenant
    return if tenant_id.blank?

    if lead_pipeline_stage_automation.present? && lead_pipeline_stage_automation.tenant_id != tenant_id
      errors.add(:lead_pipeline_stage_automation, "deve pertencer ao mesmo Tenant")
    end

    errors.add(:lead, "deve pertencer ao mesmo Tenant") if lead.present? && lead.tenant_id != tenant_id

    if lead_pipeline_stage.present? && lead_pipeline_stage.tenant_id != tenant_id
      errors.add(:lead_pipeline_stage, "deve pertencer ao mesmo Tenant")
    end
  end
end
