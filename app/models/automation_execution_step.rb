class AutomationExecutionStep < ApplicationRecord
  STATUSES = %w[pending running waiting completed failed skipped canceled].freeze

  belongs_to :automation_execution

  validates :node_id, :node_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  def status_label
    {
      "pending" => "Pendente",
      "running" => "Executando",
      "waiting" => "Aguardando",
      "completed" => "Concluida",
      "failed" => "Erro",
      "skipped" => "Ignorada",
      "canceled" => "Cancelada"
    }[status] || status
  end
end
