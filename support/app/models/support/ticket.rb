class Support::Ticket < ActiveRecord::Base
  self.table_name = "support_tickets"
  STATUSES = %w[aberto em_atendimento aguardando_usuario resolvido].freeze
  STATUS_LABELS = { "aberto" => "Aberto", "em_atendimento" => "Em atendimento", "aguardando_usuario" => "Aguardando usuário", "resolvido" => "Resolvido" }.freeze
  PRIORITIES = %w[baixa normal alta].freeze
  QUESTIONS = { "attempted_action" => "O que você tentou fazer?", "menu_module" => "Em qual tela você estava?", "expected_result" => "O que deveria acontecer?", "actual_result" => "O que aconteceu?", "impact" => "Você consegue continuar trabalhando?" }.freeze
  belongs_to :account, class_name: "Support::Account"
  has_many :messages, -> { order(:created_at, :id) }, class_name: "Support::Message", dependent: :restrict_with_exception
  has_many :deliveries, class_name: "Support::Delivery", dependent: :restrict_with_exception
  scope :ongoing, -> { where.not(status: "resolvido") }
  scope :unread_responses, -> { where("EXISTS (SELECT 1 FROM support_messages m WHERE m.ticket_id = support_tickets.id AND m.side = 'support' AND m.internal = false AND m.created_at > COALESCE(support_tickets.read_at, support_tickets.created_at))") }
  before_validation { self.uid ||= SecureRandom.uuid }
  validates :uid, :subject, :requester_id, :requester_name, presence: true
  validates :subject, length: { maximum: 180 }
  validates :uid, format: { with: /\A[0-9a-f-]{36}\z/ }
  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }
  validates :origin, inclusion: { in: %w[ativo receptivo] }
  validates :labels, length: { maximum: 300 }
  validate do
    errors.add(:diagnostics, "inválido") unless diagnostics.is_a?(Hash) && diagnostics.to_json.bytesize <= 8192
    errors.add(:intake, "conteúdo muito longo") if intake.values.any? { |v| !v.is_a?(String) || v.length > 4000 }
    QUESTIONS.each { |key, label| errors.add(:base, "#{label} Preencha este campo.") if intake[key].blank? }
    errors.add(:base, "Chamado resolvido não pode ser alterado") if persisted? && status_in_database == "resolvido" && (changes.keys - %w[read_at updated_at revision assignee_id assignee_name]).any?
  end

  def resolved? = status == "resolvido"
  def failed? = deliveries.where.not(failed_at: nil).exists?
  def pending? = deliveries.where(delivered_at: nil, failed_at: nil).exists?
end
