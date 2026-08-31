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

  ACTION_TYPES = {
    "move_stage" => "Mover para etapa",
    "archive_lead" => "Arquivar lead",
    "redistribute_lead" => "Redistribuir na fila",
    "make_available_for_automation" => "Disponibilizar para automação",
    "create_task" => "Criar tarefa",
    "add_note" => "Registrar nota"
  }.freeze

  belongs_to :lead_pipeline_stage
  belongs_to :auto_advance_to_stage,
             class_name: "LeadPipelineStage",
             optional: true
  has_many :executions,
           class_name: "LeadPipelineStageAutomationExecution",
           dependent: :destroy,
           inverse_of: :lead_pipeline_stage_automation

  validates :trigger, inclusion: { in: TRIGGERS.keys }
  validates :after_unit, inclusion: { in: UNITS.keys }
  validates :action_type, inclusion: { in: ACTION_TYPES.keys }
  validates :after_amount, numericality: { only_integer: true, greater_than: 0 }
  validates :auto_advance_to_stage, presence: true, if: :move_stage?
  validate :records_must_belong_to_tenant

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql("position ASC NULLS LAST"), :id) }

  before_validation :normalize_action_config
  before_validation :assign_position, on: :create

  def move_stage?
    action_type.to_s == "move_stage"
  end

  def action_label
    ACTION_TYPES[action_type] || action_type.to_s.humanize
  end

  def duration
    case after_unit
    when "minutes" then after_amount.minutes
    when "hours" then after_amount.hours
    else after_amount.days
    end
  end

  def unsuccessful_attempt_limit
    action_config.to_h["unsuccessful_attempt_limit"].to_i
  end

  def unsuccessful_attempt_limit?
    unsuccessful_attempt_limit.positive?
  end

  private

  def normalize_action_config
    self.action_type = "move_stage" if action_type.blank?
    self.action_config = {} unless action_config.is_a?(Hash)
    limit = action_config["unsuccessful_attempt_limit"].to_i
    self.action_config = if limit.positive?
                           action_config.merge("unsuccessful_attempt_limit" => limit)
                         else
                           action_config.except("unsuccessful_attempt_limit")
                         end
  end

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
