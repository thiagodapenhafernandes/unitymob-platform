class Proposal < ApplicationRecord
  STATUSES = %w[rascunho enviada visualizada aceita recusada expirada].freeze
  STATUS_LABELS = {
    "rascunho" => "Rascunho",
    "enviada" => "Enviada",
    "visualizada" => "Visualizada",
    "aceita" => "Aceita",
    "recusada" => "Recusada",
    "expirada" => "Expirada"
  }.freeze

  belongs_to :lead
  belongs_to :habitation, optional: true
  belongs_to :admin_user

  validates :public_token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :ensure_token, on: :create

  scope :ordered, -> { order(created_at: :desc) }

  def valor = valor_cents.to_i / 100.0
  def entrada = entrada_cents.to_i / 100.0

  def valor=(value)
    self.valor_cents = parse_money(value)
  end

  def entrada=(value)
    self.entrada_cents = parse_money(value)
  end

  def status_label = STATUS_LABELS[status] || status
  def expired? = validade.present? && validade < Date.current

  def mark_sent!
    update!(status: "enviada", sent_at: Time.current) unless status == "aceita" || status == "recusada"
    LeadActivity.log!(lead: lead, kind: "proposal_sent", metadata: { proposal_id: id, token: public_token })
  end

  def mark_viewed!
    return if viewed_at.present?
    new_status = status == "enviada" ? "visualizada" : status
    update_columns(viewed_at: Time.current, status: new_status, updated_at: Time.current)
    LeadActivity.log!(lead: lead, kind: "proposal_viewed", metadata: { proposal_id: id })
    Automation::Dispatcher.dispatch(
      :proposal_viewed,
      lead,
      source: "proposal",
      payload: { proposal_id: id },
      idempotency_key: "proposal_viewed:#{id}"
    )
  end

  def decide!(decision)
    new_status = decision.to_s == "aceita" ? "aceita" : "recusada"
    update!(status: new_status, responded_at: Time.current)
    LeadActivity.log!(lead: lead, kind: "proposal_#{new_status}", metadata: { proposal_id: id })
    Automation::Dispatcher.dispatch(
      new_status == "aceita" ? :proposal_accepted : :proposal_rejected,
      lead,
      source: "proposal",
      payload: { proposal_id: id, status: new_status },
      idempotency_key: "proposal_decision:#{id}:#{new_status}"
    )
  end

  private

  def parse_money(value)
    return 0 if value.blank?
    digits = value.to_s.gsub(/[^\d,\.]/, "")
    # Trata formato BR (1.234,56) e simples
    if digits.include?(",")
      digits = digits.delete(".").tr(",", ".")
    end
    (digits.to_f * 100).round
  end

  def ensure_token
    return if public_token.present?
    loop do
      candidate = SecureRandom.alphanumeric(8).upcase
      break self.public_token = candidate unless Proposal.exists?(public_token: candidate)
    end
  end
end
