class LeadPipelineStageTransition < ApplicationRecord
  include TenantScoped

  belongs_to :lead_pipeline_stage
  belongs_to :next_stage, class_name: "LeadPipelineStage"

  validates :next_stage_id, uniqueness: { scope: [:tenant_id, :lead_pipeline_stage_id] }
  validate :records_must_belong_to_tenant
  validate :next_stage_must_be_different

  scope :ordered, -> { order(Arel.sql("position ASC NULLS LAST"), :id) }

  private

  def records_must_belong_to_tenant
    return if tenant_id.blank?

    if lead_pipeline_stage.present? && lead_pipeline_stage.tenant_id != tenant_id
      errors.add(:lead_pipeline_stage, "deve pertencer ao mesmo Tenant")
    end

    if next_stage.present? && next_stage.tenant_id != tenant_id
      errors.add(:next_stage, "deve pertencer ao mesmo Tenant")
    end
  end

  def next_stage_must_be_different
    return if lead_pipeline_stage_id.blank? || next_stage_id.blank?

    errors.add(:next_stage, "deve ser diferente da etapa atual") if lead_pipeline_stage_id == next_stage_id
  end
end
