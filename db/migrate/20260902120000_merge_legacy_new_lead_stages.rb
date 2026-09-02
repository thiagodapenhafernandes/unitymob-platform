class MergeLegacyNewLeadStages < ActiveRecord::Migration[7.1]
  class MigrationLeadPipeline < ActiveRecord::Base
    self.table_name = "lead_pipelines"

    has_many :stages, class_name: "MergeLegacyNewLeadStages::MigrationLeadPipelineStage", foreign_key: :lead_pipeline_id
  end

  class MigrationLeadPipelineStage < ActiveRecord::Base
    self.table_name = "lead_pipeline_stages"
  end

  class MigrationLead < ActiveRecord::Base
    self.table_name = "leads"
  end

  def up
    reset_column_information!

    MigrationLeadPipeline.find_each do |pipeline|
      target_stage = stage_named(pipeline, "Novo Lead")
      next if target_stage.blank?

      legacy_stage = stage_named(pipeline, "Novo")
      move_legacy_leads!(pipeline, target_stage, legacy_stage)
      legacy_stage&.update_columns(active: false, updated_at: Time.current)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def reset_column_information!
    [MigrationLeadPipeline, MigrationLeadPipelineStage, MigrationLead].each(&:reset_column_information)
  end

  def stage_named(pipeline, name)
    pipeline.stages
      .where("LOWER(name) = ?", name.downcase)
      .order(Arel.sql("position ASC NULLS LAST"), :id)
      .first
  end

  def move_legacy_leads!(pipeline, target_stage, legacy_stage)
    scope = MigrationLead.where(tenant_id: pipeline.tenant_id, lead_pipeline_id: pipeline.id)
    scope = scope.or(MigrationLead.where(tenant_id: pipeline.tenant_id, lead_pipeline_id: nil)) if pipeline.default_general?

    legacy_scope = scope.where(status: "Novo")
    legacy_scope = legacy_scope.or(scope.where(lead_pipeline_stage_id: legacy_stage.id)) if legacy_stage.present?

    legacy_scope.update_all(
      lead_pipeline_id: pipeline.id,
      lead_pipeline_stage_id: target_stage.id,
      status: target_stage.name,
      updated_at: Time.current
    )
  end
end
