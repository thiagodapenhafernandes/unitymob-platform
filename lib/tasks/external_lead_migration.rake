namespace :external_lead_migration do
  desc "Reconcilia tarefas e visitas agendadas importadas do C2S. Use EXECUTE=1 para gravar."
  task reconcile_scheduled_actions: :environment do
    tenant = Tenant.find(ENV["TENANT_ID"]) if ENV["TENANT_ID"].present?
    integration = ExternalLeadIntegration.find(ENV["INTEGRATION_ID"]) if ENV["INTEGRATION_ID"].present?
    execute = ENV["EXECUTE"].to_s == "1"
    operational_only = ENV["OPERATIONAL_ONLY"].to_s == "1"

    result = ExternalLeadMigration::ScheduledActionReconciler.call(
      tenant: tenant,
      integration: integration,
      execute: execute,
      operational_only: operational_only
    )

    puts(
      {
        mode: execute ? "execute" : "dry_run",
        tenant_id: tenant&.id || integration&.tenant_id || "all",
        integration_id: integration&.id,
        operational_only: operational_only,
        scanned: result.scanned,
        tasks_updated: result.tasks_updated,
        tasks_created: result.tasks_created,
        tasks_reassigned: result.tasks_reassigned,
        appointments_updated: result.appointments_updated,
        appointments_created: result.appointments_created,
        appointments_reassigned: result.appointments_reassigned,
        tasks_cancelled: result.tasks_cancelled,
        skipped: result.skipped,
        skipped_non_operational: result.skipped_non_operational
      }.to_json
    )
  end

  desc "Reconcilia etiquetas importadas do C2S para etiquetas nativas dos leads. Use EXECUTE=1 para gravar."
  task reconcile_labels: :environment do
    tenant = Tenant.find_by(id: ENV["TENANT_ID"]) if ENV["TENANT_ID"].present?
    integration = ExternalLeadIntegration.find_by(id: ENV["INTEGRATION_ID"]) if ENV["INTEGRATION_ID"].present?
    execute = ENV["EXECUTE"].to_s == "1"

    result = ExternalLeadMigration::LabelReconciler.call(
      tenant: tenant,
      integration: integration,
      execute: execute
    )

    puts(
      {
        mode: execute ? "execute" : "dry_run",
        tenant_id: tenant&.id || integration&.tenant_id || "all",
        integration_id: integration&.id,
        scanned: result.scanned,
        labels_created: result.labels_created,
        labelings_created: result.labelings_created,
        skipped: result.skipped
      }.to_json
    )
  end

  desc "Reconcilia o corretor local dos leads C2S a partir do seller salvo no payload. Use EXECUTE=1 para gravar."
  task reconcile_owners: :environment do
    tenant = Tenant.find_by(id: ENV["TENANT_ID"]) if ENV["TENANT_ID"].present?
    integration = ExternalLeadIntegration.find_by(id: ENV["INTEGRATION_ID"]) if ENV["INTEGRATION_ID"].present?
    execute = ENV["EXECUTE"].to_s == "1"
    operational_only = ENV["OPERATIONAL_ONLY"].to_s == "1"

    result = ExternalLeadMigration::OwnerReconciler.call(
      tenant: tenant,
      integration: integration,
      execute: execute,
      operational_only: operational_only
    )

    puts(
      {
        mode: execute ? "execute" : "dry_run",
        tenant_id: tenant&.id || integration&.tenant_id || "all",
        integration_id: integration&.id,
        operational_only: operational_only,
        scanned: result.scanned,
        assigned: result.assigned,
        skipped: result.skipped,
        skipped_non_operational: result.skipped_non_operational,
        unmapped: result.unmapped
      }.to_json
    )
  end
end
