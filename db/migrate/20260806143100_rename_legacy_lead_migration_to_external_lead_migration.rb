class RenameLegacyLeadMigrationToExternalLeadMigration < ActiveRecord::Migration[7.1]
  LEGACY_PREFIX = "c" + "2s"

  def up
    rename_table_if_needed(:"#{LEGACY_PREFIX}_integrations", :external_lead_integrations)

    rename_column_if_needed(:leads, :"#{LEGACY_PREFIX}_integration_id", :external_lead_integration_id)
    rename_column_if_needed(:leads, :"#{LEGACY_PREFIX}_lead_id", :external_lead_id)
    rename_column_if_needed(:leads, :"#{LEGACY_PREFIX}_internal_id", :external_internal_id)
    rename_column_if_needed(:leads, :"#{LEGACY_PREFIX}_last_synced_at", :external_last_synced_at)
    rename_column_if_needed(:leads, :"client_#{LEGACY_PREFIX}_id", :client_external_id)
    rename_column_if_needed(:leads, :"agent_#{LEGACY_PREFIX}_id", :agent_external_id)

    rename_index_if_needed(:external_lead_integrations, :"index_#{LEGACY_PREFIX}_integrations_on_tenant_id", :index_external_lead_integrations_on_tenant_id)
    rename_index_if_needed(:external_lead_integrations, :"index_#{LEGACY_PREFIX}_integrations_on_distribution_rule_id", :index_external_lead_integrations_on_distribution_rule_id)
    rename_index_if_needed(:external_lead_integrations, :"index_#{LEGACY_PREFIX}_integrations_on_connected_by_admin_user_id", :idx_external_lead_integrations_connected_by_admin)
    rename_index_if_needed(:external_lead_integrations, :"index_#{LEGACY_PREFIX}_integrations_on_webhook_token", :index_external_lead_integrations_on_webhook_token)
    rename_index_if_needed(:leads, :"index_leads_on_#{LEGACY_PREFIX}_integration_id", :index_leads_on_external_lead_integration_id)
    rename_index_if_needed(:leads, :"index_leads_on_#{LEGACY_PREFIX}_internal_id", :index_leads_on_external_internal_id)
    rename_index_if_needed(:leads, :"index_leads_on_tenant_#{LEGACY_PREFIX}_lead_id", :index_leads_on_tenant_external_lead_id)
    rename_index_if_needed(:leads, :"index_leads_on_client_#{LEGACY_PREFIX}_id", :index_leads_on_client_external_id)
  end

  def down
    rename_index_if_needed(:leads, :index_leads_on_client_external_id, :"index_leads_on_client_#{LEGACY_PREFIX}_id")
    rename_index_if_needed(:leads, :index_leads_on_tenant_external_lead_id, :"index_leads_on_tenant_#{LEGACY_PREFIX}_lead_id")
    rename_index_if_needed(:leads, :index_leads_on_external_internal_id, :"index_leads_on_#{LEGACY_PREFIX}_internal_id")
    rename_index_if_needed(:leads, :index_leads_on_external_lead_integration_id, :"index_leads_on_#{LEGACY_PREFIX}_integration_id")
    rename_index_if_needed(:external_lead_integrations, :index_external_lead_integrations_on_webhook_token, :"index_#{LEGACY_PREFIX}_integrations_on_webhook_token")
    rename_index_if_needed(:external_lead_integrations, :idx_external_lead_integrations_connected_by_admin, :"index_#{LEGACY_PREFIX}_integrations_on_connected_by_admin_user_id")
    rename_index_if_needed(:external_lead_integrations, :index_external_lead_integrations_on_distribution_rule_id, :"index_#{LEGACY_PREFIX}_integrations_on_distribution_rule_id")
    rename_index_if_needed(:external_lead_integrations, :index_external_lead_integrations_on_tenant_id, :"index_#{LEGACY_PREFIX}_integrations_on_tenant_id")

    rename_column_if_needed(:leads, :agent_external_id, :"agent_#{LEGACY_PREFIX}_id")
    rename_column_if_needed(:leads, :client_external_id, :"client_#{LEGACY_PREFIX}_id")
    rename_column_if_needed(:leads, :external_last_synced_at, :"#{LEGACY_PREFIX}_last_synced_at")
    rename_column_if_needed(:leads, :external_internal_id, :"#{LEGACY_PREFIX}_internal_id")
    rename_column_if_needed(:leads, :external_lead_id, :"#{LEGACY_PREFIX}_lead_id")
    rename_column_if_needed(:leads, :external_lead_integration_id, :"#{LEGACY_PREFIX}_integration_id")

    rename_table_if_needed(:external_lead_integrations, :"#{LEGACY_PREFIX}_integrations")
  end

  private

  def rename_table_if_needed(from, to)
    rename_table(from, to) if table_exists?(from) && !table_exists?(to)
  end

  def rename_column_if_needed(table, from, to)
    return unless table_exists?(table)
    return unless column_exists?(table, from)
    return if column_exists?(table, to)

    rename_column(table, from, to)
  end

  def rename_index_if_needed(table, from, to)
    return unless table_exists?(table)
    return unless index_name_exists?(table, from)
    return if index_name_exists?(table, to)

    rename_index(table, from, to)
  end
end
