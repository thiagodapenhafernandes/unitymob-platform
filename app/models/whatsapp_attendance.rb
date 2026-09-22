# Atendimento aberto por um botão de fluxo de resposta: prende a conversa a um
# dono (rodízio entre agent_ids) até o atendente clicar em "Finalizar atendimento".
class WhatsappAttendance < ApplicationRecord
  include TenantScoped

  belongs_to :whatsapp_conversation
  belongs_to :whatsapp_response_flow, optional: true
  belongs_to :lead, optional: true
  belongs_to :distribution_rule, optional: true
  belongs_to :admin_user, optional: true
  belongs_to :closed_by, class_name: "AdminUser", optional: true

  STATUSES = %w[open closed].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :open_now, -> { where(status: "open") }

  CLOSE_REASONS = {
    "finished" => "Finalizado",
    "switched_by_customer" => "Encerrado a pedido do cliente (novo assunto)",
    "window_expired" => "Encerrado: a janela de 24h do WhatsApp fechou"
  }.freeze

  # Colegas para quem o atendimento pode ser transferido à mão: o grupo do botão (ou os elegíveis da regra); sem regra, qualquer usuário ativo.
  def transfer_candidates
    users = tenant.admin_users.active.where.not(id: admin_user_id)
    return users.order(:name) unless distribution_rule

    eligible = distribution_rule.eligible_distribution_rule_agents
    eligible = eligible.where(admin_user_id: agent_ids) if agent_ids.present?
    users.where(id: eligible.select(:admin_user_id)).order(:name)
  end

  def open? = status == "open"
  def closed? = status == "closed"

  def close_reason_label
    label = CLOSE_REASONS.fetch(close_reason.to_s, "Encerrado")
    close_reason == "finished" && closed_by ? "#{label} por #{closed_by.name}" : label
  end
  def accepted? = accepted_at.present?

  # Shark Tank/represamento podem deixar o dono só no lead.
  def owner
    admin_user || whatsapp_conversation.lead&.admin_user
  end
end
