class AddWebhookListeningEnabledToExternalLeadIntegrations < ActiveRecord::Migration[7.1]
  def change
    return unless table_exists?(:external_lead_integrations)
    return if column_exists?(:external_lead_integrations, :webhook_listening_enabled)

    add_column :external_lead_integrations, :webhook_listening_enabled, :boolean, null: false, default: false
  end
end
