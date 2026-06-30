class AddTenantToOperationalRecords < ActiveRecord::Migration[7.1]
  OPERATIONAL_TABLES = %i[
    leads
    habitations
    tasks
    appointments
    whatsapp_campaigns
    whatsapp_campaign_recipients
    whatsapp_campaign_messages
    whatsapp_campaign_unsubscribes
    whatsapp_conversations
    whatsapp_messages
    automation_rules
    automation_workflows
    automation_workflow_versions
    automation_events
    automation_executions
    automation_execution_steps
    distribution_rules
    distribution_rule_agents
    stores
    store_shifts
    check_ins
    manual_checkin_requests
    checkin_audit_logs
    proprietors
    access_audit_logs
    data_export_audit_logs
    habitation_audit_logs
    lead_audit_logs
    lead_activities
    habitation_exports
  ].freeze

  APPEND_ONLY_TABLES = %i[
    access_audit_logs
    checkin_audit_logs
    data_export_audit_logs
    habitation_audit_logs
    lead_audit_logs
  ].freeze

  def up
    default_tenant_id = default_tenant

    OPERATIONAL_TABLES.each do |table_name|
      next unless table_exists?(table_name)
      next if column_exists?(table_name, :tenant_id)

      add_reference table_name, :tenant, foreign_key: true
    end

    disable_append_only_triggers
    begin
      perform_admin_user_backfill(default_tenant_id)
      perform_created_by_backfill(default_tenant_id)
      perform_leads_backfill(default_tenant_id)
      perform_habitations_backfill(default_tenant_id)
      perform_whatsapp_campaigns_backfill(default_tenant_id)
      perform_whatsapp_conversations_backfill(default_tenant_id)
      perform_automation_backfill(default_tenant_id)
      perform_distribution_rules_backfill(default_tenant_id)
      perform_stores_backfill(default_tenant_id)
      perform_remaining_backfill(default_tenant_id)
    ensure
      enable_append_only_triggers
    end

    OPERATIONAL_TABLES.each do |table_name|
      next unless table_exists?(table_name)
      next unless column_exists?(table_name, :tenant_id)

      change_column_null table_name, :tenant_id, false
    end

    add_composite_indexes
  end

  def down
    remove_composite_indexes

    OPERATIONAL_TABLES.reverse_each do |table_name|
      next unless table_exists?(table_name)
      next unless column_exists?(table_name, :tenant_id)

      remove_reference table_name, :tenant, foreign_key: true
    end
  end

  private

  def default_tenant
    select_value("SELECT id FROM tenants WHERE slug = 'default' LIMIT 1").presence ||
      select_value("INSERT INTO tenants (name, slug, active, created_at, updated_at) VALUES ('Conta principal', 'default', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id")
  end

  def update_from_user(table_name, user_column)
    return unless table_exists?(table_name) && column_exists?(table_name, user_column) && column_exists?(table_name, :tenant_id)

    execute(<<~SQL.squish)
      UPDATE #{table_name}
      SET tenant_id = admin_users.tenant_id
      FROM admin_users
      WHERE #{table_name}.tenant_id IS NULL
        AND #{table_name}.#{user_column} = admin_users.id
    SQL
  end

  def perform_admin_user_backfill(default_tenant_id)
    update_from_user(:leads, :admin_user_id)
    update_from_user(:habitations, :admin_user_id)
    update_from_user(:tasks, :admin_user_id)
    update_from_user(:appointments, :admin_user_id)
    update_from_user(:whatsapp_campaign_recipients, :admin_user_id)
    update_from_user(:whatsapp_messages, :admin_user_id)
    update_from_user(:access_audit_logs, :admin_user_id)
    update_from_user(:data_export_audit_logs, :admin_user_id)
    update_from_user(:habitation_audit_logs, :admin_user_id)
    update_from_user(:lead_audit_logs, :admin_user_id)
    update_from_user(:lead_activities, :admin_user_id)
    update_from_user(:habitation_exports, :admin_user_id)
    update_from_user(:store_shifts, :admin_user_id)
    update_from_user(:check_ins, :admin_user_id)
    update_from_user(:manual_checkin_requests, :admin_user_id)
    update_from_user(:distribution_rule_agents, :admin_user_id)
    update_from_user(:stores, :director_admin_user_id)
    update_from_user(:whatsapp_campaign_unsubscribes, :reenabled_by_id)

    execute_default_for(:access_audit_logs, default_tenant_id)
  end

  def perform_created_by_backfill(_default_tenant_id)
    update_from_user(:whatsapp_campaigns, :created_by_id)
    update_from_user(:automation_workflows, :created_by_id)
    update_from_user(:automation_workflow_versions, :created_by_id)
    update_from_user(:automation_workflow_versions, :published_by_id)
    update_from_user(:tasks, :created_by_id)
  end

  def perform_leads_backfill(_default_tenant_id)
    update_from_table(:tasks, :lead_id, :leads)
    update_from_table(:appointments, :lead_id, :leads)
    update_from_table(:whatsapp_conversations, :lead_id, :leads)
    update_from_table(:whatsapp_campaign_recipients, :lead_id, :leads)
    update_from_table(:automation_events, :lead_id, :leads)
    update_from_table(:lead_activities, :lead_id, :leads)
  end

  def perform_habitations_backfill(_default_tenant_id)
    update_from_table(:appointments, :habitation_id, :habitations)
    update_from_table(:habitation_audit_logs, :habitation_id, :habitations)
  end

  def perform_whatsapp_campaigns_backfill(_default_tenant_id)
    update_from_table(:whatsapp_campaign_recipients, :whatsapp_campaign_id, :whatsapp_campaigns)
    update_from_table(:whatsapp_campaign_messages, :whatsapp_campaign_id, :whatsapp_campaigns)
    update_from_table(:whatsapp_campaign_unsubscribes, :whatsapp_campaign_id, :whatsapp_campaigns)
  end

  def perform_whatsapp_conversations_backfill(_default_tenant_id)
    update_from_table(:whatsapp_messages, :whatsapp_conversation_id, :whatsapp_conversations)
  end

  def perform_automation_backfill(_default_tenant_id)
    update_from_table(:automation_workflow_versions, :automation_workflow_id, :automation_workflows)
    update_from_table(:automation_executions, :automation_workflow_id, :automation_workflows)
    update_from_table(:automation_executions, :automation_event_id, :automation_events)
    update_from_table(:automation_execution_steps, :automation_execution_id, :automation_executions)
  end

  def perform_distribution_rules_backfill(_default_tenant_id)
    update_from_table(:leads, :distribution_rule_id, :distribution_rules)
    update_from_table(:distribution_rule_agents, :distribution_rule_id, :distribution_rules)
  end

  def perform_stores_backfill(_default_tenant_id)
    update_from_table(:store_shifts, :store_id, :stores)
    update_from_table(:check_ins, :store_id, :stores)
  end

  def perform_remaining_backfill(default_tenant_id)
    OPERATIONAL_TABLES.each do |table_name|
      execute_default_for(table_name, default_tenant_id)
    end
  end

  def update_from_table(table_name, foreign_key, source_table)
    return unless table_exists?(table_name) && table_exists?(source_table)
    return unless column_exists?(table_name, foreign_key) && column_exists?(table_name, :tenant_id) && column_exists?(source_table, :tenant_id)

    execute(<<~SQL.squish)
      UPDATE #{table_name}
      SET tenant_id = #{source_table}.tenant_id
      FROM #{source_table}
      WHERE #{table_name}.tenant_id IS NULL
        AND #{table_name}.#{foreign_key} = #{source_table}.id
    SQL
  end

  def execute_default_for(table_name, default_tenant_id)
    return unless table_exists?(table_name) && column_exists?(table_name, :tenant_id)

    execute("UPDATE #{table_name} SET tenant_id = #{default_tenant_id.to_i} WHERE tenant_id IS NULL")
  end

  def disable_append_only_triggers
    APPEND_ONLY_TABLES.each do |table_name|
      execute("ALTER TABLE #{table_name} DISABLE TRIGGER USER") if table_exists?(table_name)
    end
  end

  def enable_append_only_triggers
    APPEND_ONLY_TABLES.each do |table_name|
      execute("ALTER TABLE #{table_name} ENABLE TRIGGER USER") if table_exists?(table_name)
    end
  end

  def add_composite_indexes
    add_index_if_possible :leads, [:tenant_id, :admin_user_id]
    add_index_if_possible :habitations, [:tenant_id, :admin_user_id]
    add_index_if_possible :tasks, [:tenant_id, :admin_user_id]
    add_index_if_possible :appointments, [:tenant_id, :admin_user_id]
    add_index_if_possible :whatsapp_campaigns, [:tenant_id, :created_by_id]
    add_index_if_possible :whatsapp_campaign_recipients, [:tenant_id, :whatsapp_campaign_id]
    add_index_if_possible :whatsapp_campaign_messages, [:tenant_id, :whatsapp_campaign_id]
    add_index_if_possible :whatsapp_campaign_unsubscribes, [:tenant_id, :whatsapp_campaign_id]
    add_index_if_possible :whatsapp_conversations, [:tenant_id, :lead_id]
    add_index_if_possible :whatsapp_messages, [:tenant_id, :whatsapp_conversation_id]
    add_index_if_possible :automation_workflows, [:tenant_id, :status]
    add_index_if_possible :automation_workflow_versions, [:tenant_id, :automation_workflow_id]
    add_index_if_possible :automation_executions, [:tenant_id, :automation_workflow_id]
    add_index_if_possible :automation_execution_steps, [:tenant_id, :automation_execution_id]
    add_index_if_possible :automation_rules, [:tenant_id, :trigger_event]
    add_index_if_possible :distribution_rules, [:tenant_id, :active]
    add_index_if_possible :stores, [:tenant_id, :active]
    add_index_if_possible :proprietors, [:tenant_id, :name]
  end

  def remove_composite_indexes
    remove_index_if_exists :proprietors, [:tenant_id, :name]
    remove_index_if_exists :stores, [:tenant_id, :active]
    remove_index_if_exists :distribution_rules, [:tenant_id, :active]
    remove_index_if_exists :automation_rules, [:tenant_id, :trigger_event]
    remove_index_if_exists :automation_execution_steps, [:tenant_id, :automation_execution_id]
    remove_index_if_exists :automation_executions, [:tenant_id, :automation_workflow_id]
    remove_index_if_exists :automation_workflow_versions, [:tenant_id, :automation_workflow_id]
    remove_index_if_exists :automation_workflows, [:tenant_id, :status]
    remove_index_if_exists :whatsapp_messages, [:tenant_id, :whatsapp_conversation_id]
    remove_index_if_exists :whatsapp_conversations, [:tenant_id, :lead_id]
    remove_index_if_exists :whatsapp_campaign_unsubscribes, [:tenant_id, :whatsapp_campaign_id]
    remove_index_if_exists :whatsapp_campaign_messages, [:tenant_id, :whatsapp_campaign_id]
    remove_index_if_exists :whatsapp_campaign_recipients, [:tenant_id, :whatsapp_campaign_id]
    remove_index_if_exists :whatsapp_campaigns, [:tenant_id, :created_by_id]
    remove_index_if_exists :appointments, [:tenant_id, :admin_user_id]
    remove_index_if_exists :tasks, [:tenant_id, :admin_user_id]
    remove_index_if_exists :habitations, [:tenant_id, :admin_user_id]
    remove_index_if_exists :leads, [:tenant_id, :admin_user_id]
  end

  def add_index_if_possible(table_name, columns)
    return unless table_exists?(table_name)
    return unless columns.all? { |column| column_exists?(table_name, column) }
    return if index_exists?(table_name, columns)

    add_index table_name, columns
  end

  def remove_index_if_exists(table_name, columns)
    return unless table_exists?(table_name)
    return unless index_exists?(table_name, columns)

    remove_index table_name, column: columns
  end
end
