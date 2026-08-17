class LeadPipelineStageAutomation < ApplicationRecord
  include TenantScoped

  TRIGGERS = {
    "stage_duration" => "Tempo na etapa",
    "general_inactivity" => "Inatividade geral",
    "customer_inactivity" => "Sem interação do cliente",
    "team_inactivity" => "Sem ação do responsável",
    "no_stage_change" => "Sem avanço de etapa"
  }.freeze

  UNITS = {
    "minutes" => "minutos",
    "hours" => "horas",
    "days" => "dias"
  }.freeze

  belongs_to :lead_pipeline_stage
  belongs_to :auto_advance_to_stage,
             class_name: "LeadPipelineStage",
             optional: true

  validates :trigger, inclusion: { in: TRIGGERS.keys }
  validates :after_unit, inclusion: { in: UNITS.keys }
  validates :after_amount, numericality: { only_integer: true, greater_than: 0 }
  validates :auto_advance_to_stage, presence: true
  validate :records_must_belong_to_tenant

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql("position ASC NULLS LAST"), :id) }

  before_validation :assign_position, on: :create

  def duration
    case after_unit
    when "minutes" then after_amount.minutes
    when "hours" then after_amount.hours
    else after_amount.days
    end
  end

  private

  def assign_position
    return if position.present? || lead_pipeline_stage.blank?

    self.position = (lead_pipeline_stage.automations.maximum(:position) || -1) + 1
  end

  def records_must_belong_to_tenant
    return if tenant_id.blank?

    if lead_pipeline_stage.present? && lead_pipeline_stage.tenant_id != tenant_id
      errors.add(:lead_pipeline_stage, "deve pertencer ao mesmo Tenant")
    end

    if auto_advance_to_stage.present? && auto_advance_to_stage.tenant_id != tenant_id
      errors.add(:auto_advance_to_stage, "deve pertencer ao mesmo Tenant")
    end

    if lead_pipeline_stage_id.present? && auto_advance_to_stage_id.present? && lead_pipeline_stage_id == auto_advance_to_stage_id
      errors.add(:auto_advance_to_stage, "deve ser diferente da etapa atual")
    end
  end
end
