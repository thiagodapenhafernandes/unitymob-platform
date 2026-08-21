class LeadPipelineStage < ApplicationRecord
  include TenantScoped

  STAGE_TYPES = {
    "open" => "Aberta",
    "won" => "Ganha",
    "lost" => "Perdida",
    "archived" => "Arquivada"
  }.freeze
  HEX_COLOR = /\A#\h{6}\z/
  DEFAULT_COLORS = %w[#2f80a0 #365f8f #8a63d2 #d97706 #08875d #e0402f #667085].freeze

  belongs_to :lead_pipeline
  has_many :leads, dependent: :nullify
  has_many :automations,
           class_name: "LeadPipelineStageAutomation",
           dependent: :destroy,
           inverse_of: :lead_pipeline_stage
  has_one :policy,
          class_name: "LeadPipelineStagePolicy",
          dependent: :destroy,
          inverse_of: :lead_pipeline_stage
  has_many :transitions,
           class_name: "LeadPipelineStageTransition",
           dependent: :destroy,
           inverse_of: :lead_pipeline_stage
  has_many :automation_executions,
           class_name: "LeadPipelineStageAutomationExecution",
           dependent: :destroy,
           inverse_of: :lead_pipeline_stage
  has_many :next_stages,
           through: :transitions,
           source: :next_stage

  validates :name, presence: true, uniqueness: { scope: [:tenant_id, :lead_pipeline_id], case_sensitive: false }
  validates :stage_type, inclusion: { in: STAGE_TYPES.keys }
  validates :color, format: { with: HEX_COLOR, message: "inválida" }, allow_blank: true
  validate :pipeline_must_belong_to_tenant

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql("position ASC NULLS LAST"), :name) }

  before_validation :assign_position, on: :create
  before_validation :infer_stage_type
  after_update_commit :sync_leads_status_on_rename, if: :saved_change_to_name?

  def policy_or_default
    policy || build_policy(LeadPipelineStagePolicy.default_attributes.merge(tenant: tenant))
  end

  def visible_to_admin_user?(admin_user)
    policy_or_default.visible_to_admin_user?(admin_user)
  end

  def summary_parts
    stage_policy = policy_or_default
    parts = []
    parts << "Visível para #{stage_policy.visible_role_labels.to_sentence}" if stage_policy.visible_role_labels.any?
    parts << "#{transitions.size} próxima(s) etapa(s)" if transitions.loaded? ? transitions.any? : transitions.exists?
    archive_automation = automations.active.where(action_type: "archive_lead").ordered.first
    parts << "Arquiva em #{archive_automation.after_amount} #{LeadPipelineStageAutomation::UNITS[archive_automation.after_unit]}" if archive_automation
    parts
  end

  def display_color
    return color if color.to_s.match?(HEX_COLOR)

    DEFAULT_COLORS[position.to_i % DEFAULT_COLORS.size]
  end

  def self.matching_name(tenant:, pipeline:, name:)
    return nil if tenant.blank? || pipeline.blank? || name.blank?

    normalized = normalized_name_key(name)
    where(tenant: tenant, lead_pipeline: pipeline).detect do |stage|
      normalized_name_key(stage.name) == normalized
    end
  end

  def self.sanitize_name(value)
    value.to_s.tr("_", " ").squish.sub(/[[:space:]]*[\.,;:!?]+[[:space:]]*\z/, "")
  end

  def self.normalized_name_key(value)
    I18n.transliterate(sanitize_name(value)).downcase.parameterize(separator: "_")
  end

  private

  def assign_position
    return if position.present? || lead_pipeline.blank?

    self.position = (lead_pipeline.stages.maximum(:position) || -1) + 1
  end

  def infer_stage_type
    self.name = self.class.sanitize_name(name)
    return if stage_type.present? && will_save_change_to_stage_type?

    self.stage_type = inferred_stage_type if stage_type.blank? || will_save_change_to_name?
  end

  def inferred_stage_type
    key = self.class.normalized_name_key(name)
    return "won" if key.match?(/concluido|vendido|locado|fechado|ganho/)
    return "lost" if key.match?(/descartado|perdido|sem_interesse/)
    return "archived" if key.match?(/arquivado/)

    stage_type.presence || "open"
  end

  def pipeline_must_belong_to_tenant
    return if tenant.blank? || lead_pipeline.blank? || lead_pipeline.tenant_id == tenant_id

    errors.add(:lead_pipeline, "deve pertencer ao mesmo Tenant")
  end

  def sync_leads_status_on_rename
    leads.update_all(status: name, updated_at: Time.current)
  end
end
