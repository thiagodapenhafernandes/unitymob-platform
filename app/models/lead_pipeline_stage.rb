class LeadPipelineStage < ApplicationRecord
  include TenantScoped

  STAGE_TYPES = {
    "open" => "Aberta",
    "won" => "Ganha",
    "lost" => "Perdida",
    "archived" => "Arquivada"
  }.freeze

  belongs_to :lead_pipeline
  has_many :leads, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: [:tenant_id, :lead_pipeline_id], case_sensitive: false }
  validates :stage_type, inclusion: { in: STAGE_TYPES.keys }
  validate :pipeline_must_belong_to_tenant

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql("position ASC NULLS LAST"), :name) }

  before_validation :assign_position, on: :create
  before_validation :infer_stage_type
  after_update_commit :sync_leads_status_on_rename, if: :saved_change_to_name?

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
