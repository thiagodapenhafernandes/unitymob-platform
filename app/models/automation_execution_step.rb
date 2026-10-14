class AutomationExecutionStep < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending running waiting completed failed skipped canceled].freeze

  belongs_to :automation_execution

  validates :node_id, :node_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  def enqueue_resume!(node_ids:, scheduled_for: nil, cause: "timeout")
    ids = Array(node_ids).reject(&:blank?).map(&:to_s)
    update!(output: output.to_h.merge("resume_jobs" => ids, "resume_cause" => cause))
    ids.presence&.each do |node_id|
      Automation::RunWorkflowJob.set(wait_until: scheduled_for).perform_later(automation_execution_id, node_id, id, cause)
    end
    Automation::RunWorkflowJob.set(wait_until: scheduled_for).perform_later(automation_execution_id, nil, id, cause) if ids.empty?
  end

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
