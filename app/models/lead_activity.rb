class LeadActivity < ApplicationRecord
  include TenantScoped

  EXTERNAL_SYNC_KINDS = %w[
    external_lead_imported
    external_lead_synced
    external_first_message
    external_message
    external_log
    external_scheduled_action
    external_appointment
    c2s_imported
  ].freeze

  AUTOMATION_KINDS = %w[
    automation
    automation_event
    automation_redistribution
    automation_available
  ].freeze
  CONTACT_KIND_LABELS = {
    "ligacao" => "Ligação",
    "whatsapp" => "WhatsApp",
    "email" => "E-mail",
    "visita" => "Visita",
    "nota" => "Anotação interna",
    "note" => "Anotação interna"
  }.freeze
  CONTACT_RESULT_LABELS = {
    "nao_respondeu" => "Não respondeu",
    "falou_com_cliente" => "Falou com cliente",
    "retornar_depois" => "Retornar depois",
    "sem_interesse" => "Sem interesse"
  }.freeze
  CONTACT_ATTEMPT_KINDS = %w[ligacao whatsapp email visita].freeze
  UNSUCCESSFUL_CONTACT_RESULTS = %w[nao_respondeu sem_interesse].freeze
  SOURCE_CATEGORIES = %w[human external_sync automation].freeze

  belongs_to :lead

  validates :kind, presence: true
  validates :source_category, inclusion: { in: SOURCE_CATEGORIES }, if: -> { has_attribute?(:source_category) }

  before_validation :assign_source_category, if: -> { has_attribute?(:source_category) }

  # kinds existentes: created, distributed, accepted, rejected, comment, status_change
  # kinds comerciais: note, task_created, task_completed, appointment_created,
  #                   appointment_done, proposal_created, proposal_sent,
  #                   proposal_viewed, proposal_aceita, proposal_recusada
  # kinds atendimento (fase 2): whatsapp_in, whatsapp_out
  # kinds automação (fase 3): automation, automation_event

  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }
  scope :external_sync, -> { where(source_category: "external_sync") }
  scope :without_external_sync, -> { where.not(source_category: "external_sync") }
  scope :automation, -> { where(source_category: "automation") }
  scope :human_operational, -> { where(source_category: "human") }
  scope :contact_attempts, -> {
    where(kind: "note")
      .where("lead_activities.metadata ->> 'contact_kind' IN (?)", CONTACT_ATTEMPT_KINDS)
  }
  scope :unsuccessful_contact_attempts, -> {
    contact_attempts.where("lead_activities.metadata ->> 'contact_result' IN (?)", UNSUCCESSFUL_CONTACT_RESULTS)
  }

  # Registra um evento na timeline do lead. Nunca quebra o fluxo principal.
  def self.log!(lead:, kind:, metadata: {})
    return nil unless lead
    create!(lead: lead, kind: kind.to_s, metadata: (metadata || {}))
  rescue => e
    Rails.logger.warn("[LeadActivity.log!] #{e.class}: #{e.message}")
    nil
  end

  def meta(key)
    return nil unless metadata.is_a?(Hash)
    metadata[key.to_s]
  end

  private

  def assign_source_category
    self.source_category = inferred_source_category if source_category.blank?
  end

  def inferred_source_category
    return "external_sync" if kind.in?(EXTERNAL_SYNC_KINDS)
    return "automation" if kind.in?(AUTOMATION_KINDS)
    return "automation" if metadata.is_a?(Hash) && automation_metadata?

    "human"
  end

  def automation_metadata?
    metadata["by"].to_s.in?(["Automação", "Automação da etapa", "Inteligência de Interesse"]) ||
      metadata.key?("automation_id") ||
      metadata.key?("lead_pipeline_stage_automation_id")
  end
end
