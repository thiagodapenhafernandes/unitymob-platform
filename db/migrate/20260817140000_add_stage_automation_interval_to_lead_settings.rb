class AddStageAutomationIntervalToLeadSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_settings, :stage_automation_sweep_interval_minutes, :integer, null: false, default: 15
    add_column :lead_settings, :stage_automation_last_swept_at, :datetime
  end
end
