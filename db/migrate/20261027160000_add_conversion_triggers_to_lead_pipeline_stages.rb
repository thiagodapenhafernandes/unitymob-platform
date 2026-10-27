class AddConversionTriggersToLeadPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_pipeline_stages, :google_event_trigger, :string, null: false, default: "stage_entered"
    add_column :lead_pipeline_stages, :meta_event_trigger, :string, null: false, default: "stage_entered"
  end
end
