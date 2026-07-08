# Agendado pelo config/recurring.yml: DwvSyncJob exige tenant, então o
# recorrente faz fan-out — um DwvSyncJob por tenant com integração DWV
# habilitada (mesmo critério do Dwv::SyncRunnerService#ensure_enabled_and_token!).
# Roda na fila dwv (1 thread), que serializa os syncs e mantém coerente o
# lock global do Dwv::SyncLockService.
class DwvSyncAllTenantsJob < ApplicationJob
  queue_as :dwv

  def perform(mode: "full", limit: nil, max_pages: nil, last_updates: nil)
    Tenant.active.find_each do |tenant|
      next unless dwv_configured_for?(tenant)

      DwvSyncJob.perform_later(
        mode: mode,
        limit: limit,
        max_pages: max_pages,
        last_updates: last_updates,
        tenant_id: tenant.id
      )
    end
  end

  private

  def dwv_configured_for?(tenant)
    Setting.get("dwv_enabled", "false", tenant: tenant) == "true" &&
      Setting.get("dwv_api_token", tenant: tenant).present?
  end
end
