class AddGoogleQualificationEnabledToStages < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_pipeline_stages, :google_qualification_enabled, :boolean, null: false, default: false
  end
end
