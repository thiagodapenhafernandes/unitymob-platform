namespace :external_lead_migration do
  desc "Reconcilia tarefas e visitas agendadas importadas do C2S. Use EXECUTE=1 para gravar."
  task reconcile_scheduled_actions: :environment do
    tenant = Tenant.find_by(id: ENV["TENANT_ID"]) if ENV["TENANT_ID"].present?
    integration = ExternalLeadIntegration.find_by(id: ENV["INTEGRATION_ID"]) if ENV["INTEGRATION_ID"].present?
    execute = ENV["EXECUTE"].to_s == "1"

    result = ExternalLeadMigration::ScheduledActionReconciler.call(
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
        tasks_updated: result.tasks_updated,
        tasks_created: result.tasks_created,
        appointments_updated: result.appointments_updated,
        appointments_created: result.appointments_created,
        tasks_cancelled: result.tasks_cancelled,
        skipped: result.skipped
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
end
