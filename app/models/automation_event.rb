class AutomationEvent < ApplicationRecord
  STATUSES = %w[pending processing processed failed ignored].freeze

  belongs_to :lead, optional: true

  has_many :automation_runs, dependent: :nullify
  has_many :automation_executions, dependent: :nullify

  before_validation :set_defaults

  validates :name, presence: true
  validates :source, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, uniqueness: true, allow_blank: true

  scope :recent, -> { order(occurred_at: :desc, id: :desc) }
  scope :pending, -> { where(status: "pending") }

  def name_label
    Automation::EventCatalog.label(name)
  end

  def source_label
    {
      "lead" => "Lead",
      "distribution" => "Distribuição",
      "proposal" => "Proposta",
      "whatsapp" => "WhatsApp",
      "whatsapp_campaign" => "Disparo WhatsApp",
      "automation_tick" => "Rotina",
      "interest_intelligence" => "Inteligência de Interesse",
      "platform" => "Plataforma"
    }[source] || source.to_s.humanize
  end

  def status_label
    {
      "pending" => "Pendente",
      "processing" => "Processando",
      "processed" => "Processado",
      "failed" => "Erro",
      "ignored" => "Ignorado"
    }[status] || status
  end

  def status_color
    {
      "pending" => "amber",
      "processing" => "blue",
      "processed" => "green",
      "failed" => "red",
      "ignored" => "gray"
    }[status] || "gray"
  end

  def payload_hash
    payload.is_a?(Hash) ? payload.with_indifferent_access : {}
  end

  def pending?
    status == "pending"
  end

  def processed?
    status == "processed"
  end

  def failed?
    status == "failed"
  end

  def ignored?
    status == "ignored"
  end

  def reprocessable?
    failed?
  end

  def mark_processing!
    update!(status: "processing", error_message: nil)
  end

  def mark_processed!
    update!(status: "processed", processed_at: Time.current, error_message: nil)
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message.to_s)
  end

  private

  def set_defaults
    self.source = "platform" if source.blank?
    self.status = "pending" if status.blank?
    self.occurred_at ||= Time.current
    self.payload = {} unless payload.is_a?(Hash)
  end
end
