class Task < ApplicationRecord
  KINDS = {
    "ligacao" => "Ligação",
    "visita" => "Visita",
    "email" => "E-mail",
    "follow_up" => "Follow-up",
    "outro" => "Outro"
  }.freeze
  STATUSES = %w[pendente concluida cancelada].freeze
  PRIORITIES = { "baixa" => "Baixa", "normal" => "Normal", "alta" => "Alta" }.freeze

  belongs_to :lead, optional: true
  belongs_to :admin_user # responsável
  belongs_to :created_by, class_name: "AdminUser", optional: true

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS.keys }

  scope :pendentes, -> { where(status: "pendente") }
  scope :concluidas, -> { where(status: "concluida") }
  scope :atrasadas, -> { pendentes.where.not(due_at: nil).where("due_at < ?", Time.current) }
  scope :hoje, -> { pendentes.where(due_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :semana, -> { pendentes.where(due_at: Time.current.beginning_of_day..7.days.from_now.end_of_day) }
  scope :ordered, -> { order(Arel.sql("CASE WHEN status = 'pendente' THEN 0 ELSE 1 END, due_at ASC NULLS LAST, created_at DESC")) }

  def pendente? = status == "pendente"
  def concluida? = status == "concluida"
  def atrasada? = pendente? && due_at.present? && due_at < Time.current
  def kind_label = KINDS[kind] || kind
  def priority_label = PRIORITIES[priority] || priority

  def complete!(by: nil)
    update!(status: "concluida", completed_at: Time.current)
    LeadActivity.log!(lead: lead, kind: "task_completed", metadata: { task_id: id, title: title, by: by&.name }.compact) if lead_id
  end
end
