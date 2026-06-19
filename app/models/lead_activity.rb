class LeadActivity < ApplicationRecord
  belongs_to :lead

  validates :kind, presence: true

  # kinds existentes: created, distributed, accepted, rejected, comment, status_change
  # kinds comerciais: note, task_created, task_completed, appointment_created,
  #                   appointment_done, proposal_created, proposal_sent,
  #                   proposal_viewed, proposal_aceita, proposal_recusada
  # kinds atendimento (fase 2): whatsapp_in, whatsapp_out
  # kinds automação (fase 3): automation

  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }

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
end
