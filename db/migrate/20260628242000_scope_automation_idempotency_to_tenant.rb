class ScopeAutomationIdempotencyToTenant < ActiveRecord::Migration[7.1]
  def up
    remove_index :automation_events, name: "index_automation_events_on_idempotency_key", if_exists: true
    remove_index :automation_executions, name: "index_automation_executions_on_idempotency_key", if_exists: true

    add_index :automation_events,
              [:tenant_id, :idempotency_key],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "index_automation_events_on_tenant_id_and_idempotency_key"

    add_index :automation_executions,
              [:tenant_id, :idempotency_key],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "index_automation_execs_on_tenant_id_and_idempotency_key"
  end

  def down
    remove_index :automation_events, name: "index_automation_events_on_tenant_id_and_idempotency_key", if_exists: true
    remove_index :automation_executions, name: "index_automation_execs_on_tenant_id_and_idempotency_key", if_exists: true

    add_index :automation_events,
              :idempotency_key,
              unique: true,
              name: "index_automation_events_on_idempotency_key"

    add_index :automation_executions,
              :idempotency_key,
              unique: true,
              name: "index_automation_executions_on_idempotency_key"
  end
end
