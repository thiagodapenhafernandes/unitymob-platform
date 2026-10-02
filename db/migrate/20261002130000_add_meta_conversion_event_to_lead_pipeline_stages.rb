class AddMetaConversionEventToLeadPipelineStages < ActiveRecord::Migration[7.1]
  def up
    add_column :lead_pipeline_stages, :meta_conversion_event, :string
    # Preserva o comportamento da convenção v1 (etapa ganha => Purchase);
    # demais etapas seguem sem evento até o gestor mapear.
    LeadPipelineStage.where(stage_type: "won").update_all(meta_conversion_event: "Purchase")
  end

  def down
    remove_column :lead_pipeline_stages, :meta_conversion_event
  end
end
