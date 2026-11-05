class Task < ApplicationRecord
  include TenantScoped
  include LeadOwnerRequired
  include LeadActivityOwnership

  KINDS = {
    "ligacao" => "Ligação",
    "visita" => "Visita",
    "email" => "E-mail",
    "follow_up" => "Follow-up",
    "outro" => "Outro"
  }.freeze
  STATUSES = %w[pendente concluida cancelada].freeze
  PRIORITIES = { "baixa" => "Baixa", "normal" => "Normal", "alta" => "Alta" }.freeze
  LEGACY_EXTERNAL_TITLE = "Ação agendada do legado".freeze
  SOURCES = %w[manual external_legacy automation].freeze

  belongs_to :lead, optional: true
  belongs_to :admin_user # responsável
  belongs_to :created_by, class_name: "AdminUser", optional: true

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :source, inclusion: { in: SOURCES }, if: -> { has_attribute?(:source) }
  validate :associations_belong_to_same_tenant

  before_validation :assign_source, if: -> { has_attribute?(:source) }

  scope :pendentes, -> { where(status: "pendente") }
  scope :concluidas, -> { where(status: "concluida") }
  scope :atrasadas, -> { pendentes.where.not(due_at: nil).where("due_at < ?", Time.current) }
  scope :hoje, -> { pendentes.where(due_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :semana, -> { pendentes.where(due_at: Time.current.beginning_of_day..7.days.from_now.end_of_day) }
  scope :ordered, -> { order(Arel.sql("CASE WHEN tasks.status = 'pendente' THEN 0 ELSE 1 END, tasks.due_at ASC NULLS LAST, tasks.created_at DESC")) }
  scope :external_legacy, -> { where(source: "external_legacy") }
  scope :operational_current, -> {
    left_outer_joins(lead: :lead_pipeline_stage)
      .where(
        <<~SQL.squish,
          tasks.source IS NULL
          OR tasks.source <> :legacy_source
          OR (
            tasks.source = :legacy_source
            AND leads.id IS NOT NULL
            AND leads.status NOT IN (:non_operational_statuses)
            AND (
              lead_pipeline_stages.id IS NULL
              OR lead_pipeline_stages.stage_type = :open_stage
            )
          )
        SQL
        legacy_source: "external_legacy",
        non_operational_statuses: Lead.non_operational_status_values,
        open_stage: "open"
      )
  }

  def pendente? = status == "pendente"
  def concluida? = status == "concluida"
  def atrasada? = pendente? && due_at.present? && due_at < Time.current
  def kind_label = KINDS[kind] || kind
  def priority_label = PRIORITIES[priority] || priority
  def external_legacy? = source == "external_legacy" || title == LEGACY_EXTERNAL_TITLE || external_scheduled_activity_linked?

  def complete!(by: nil)
    change_completion!("concluida", by: by)
  end

  def reopen!(by:, reason:)
    reason = reason.to_s.strip
    if reason.blank? || reason.length > 500 || lead_id.blank?
      errors.add(:base, "Informe um motivo de até 500 caracteres para reabrir uma tarefa vinculada.")
      raise ActiveRecord::RecordInvalid, self
    end

    change_completion!("pendente", by: by, reason: reason)
  end

  private

  def change_completion!(new_status, by:, reason: nil)
    transaction do
      expected_lead_id = lead_id
      linked_lead = lead
      linked_lead&.lock!
      lock!
      if lead_id != expected_lead_id
        errors.add(:base, "O vínculo da tarefa mudou. Atualize a página e tente novamente.")
        raise ActiveRecord::RecordInvalid, self
      end
      next if status == new_status

      completing = new_status == "concluida"
      unless completing ? pendente? : concluida?
        errors.add(:base, "O status atual não permite esta ação.")
        raise ActiveRecord::RecordInvalid, self
      end

      update!(status: new_status, completed_at: completing ? Time.current : nil)
      if linked_lead
        linked_lead.activities.create!(
          tenant_id: tenant_id,
          kind: completing ? "task_completed" : "task_reopened",
          metadata: { task_id: id, title: title, by: by&.name, actor_id: by&.id, reason: reason }.compact
        )
      end
    end
  end

  def assign_source
    self.source = "external_legacy" if source.blank? && title == LEGACY_EXTERNAL_TITLE
    self.source ||= "manual"
  end

  def external_scheduled_activity_linked?
    return false unless id && lead_id

    lead.activities.where(kind: "external_scheduled_action").where("metadata @> ?", { task_id: id }.to_json).exists?
  end

  def associations_belong_to_same_tenant
    {
      admin_user: admin_user,
      created_by: created_by,
      lead: lead
    }.each do |name, record|
      next if record.blank? || tenant.blank? || record.tenant_id == tenant_id

      errors.add(name, "deve pertencer à mesma conta da tarefa")
    end
  end
end
