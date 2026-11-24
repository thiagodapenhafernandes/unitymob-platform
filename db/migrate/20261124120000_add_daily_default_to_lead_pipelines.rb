class AddDailyDefaultToLeadPipelines < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_pipelines, :default_for_daily, :boolean, null: false, default: false
    add_index :lead_pipelines, :tenant_id, unique: true,
      where: "default_for_daily = TRUE", name: "index_lead_pipelines_daily_default_per_tenant"
  end
end
