class AddNonFidelizingStageIdsToLeadSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_settings, :stickiness_non_fidelizing_stage_ids, :bigint, array: true, default: [], null: false
  end
end
