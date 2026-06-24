class AutomationExecution < ApplicationRecord
  STATUSES = %w[pending running waiting completed failed canceled].freeze

  belongs_to :automation_workflow
  belongs_to :automation_workflow_version
  belongs_to :lead, optional: true
  belongs_to :automation_event, optional: true

  has_many :steps,
           class_name: "AutomationExecutionStep",
           dependent: :destroy,
           inverse_of: :automation_execution

  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, uniqueness: true, allow_blank: true

  scope :recent, -> { order(created_at: :desc) }

  def status_label
    {
      "pending" => "Pendente",
      "running" => "Executando",
      "waiting" => "Aguardando",
      "completed" => "Concluida",
      "failed" => "Erro",
      "canceled" => "Cancelada"
    }[status] || status
  end
end
