class AutomationRun < ApplicationRecord
  belongs_to :automation_rule
  belongs_to :lead, optional: true
  belongs_to :automation_event, optional: true

  STATUSES = %w[executed scheduled skipped error].freeze

  scope :recent, -> { order(created_at: :desc) }

  def status_label
    {
      "executed" => "Executada",
      "scheduled" => "Agendada",
      "skipped" => "Ignorada",
      "error" => "Erro"
    }[status] || status
  end
end
