class LoftImagesSyncJob < ApplicationJob
  queue_as :sync

  def perform(limit: nil, triggered_by_id: nil, tenant_id: nil)
    tenant = resolve_tenant(tenant_id: tenant_id, triggered_by_id: triggered_by_id)
    raise ArgumentError, "Tenant obrigatório para sincronização de imagens Loft" if tenant.blank?

    triggered_by = resolve_triggered_by(tenant: tenant, triggered_by_id: triggered_by_id)
    Current.tenant = tenant
    lock_service = Loft::SyncLockService.new(
      lock_key: "loft_images_sync_lock",
      lease_seconds: ENV.fetch("LOFT_IMAGES_SYNC_LOCK_LEASE_SECONDS", "3600")
    )
    lock_owner = lock_service.acquire
    status_service = Loft::SyncStatusService.new

    unless lock_owner.present?
      status_service.mark_skipped!(mode: "images", message: "Sync de imagens Loft ignorado: já existe sincronização de imagens em andamento.")
      return
    end

    status_service.mark_processing!(mode: "images", message: "Sincronização de imagens Loft iniciada.", progress: 5)

    batch_limit = limit.to_i.positive? ? limit.to_i : Setting.get("loft_images_sync_limit", "100").to_i
    batch_limit = batch_limit.clamp(1, 500)

    result = Loft::ImagesSyncService.new(tenant: tenant).call(limit: batch_limit)
    message = [
      "Loft images sync concluído",
      "processados=#{result[:processed]}",
      "sincronizados=#{result[:synced]}",
      "pulados=#{result[:skipped]}",
      "falhas=#{result[:failed]}",
      ("triggered_by=#{triggered_by.id}" if triggered_by.present?)
    ].compact.join(" | ")

    status_service.mark_completed!(
      mode: "images",
      message: message,
      stats: {
        processed: result[:processed].to_i,
        images_synced: result[:synced].to_i,
        images_skipped: result[:skipped].to_i,
        errors_count: result[:failed].to_i
      }
    )
  rescue => e
    status_service&.mark_failed!(mode: "images", message: "Loft images sync falhou: #{e.message}")
    raise e
  ensure
    lock_service&.release(lock_owner)
    Current.tenant = nil
  end

  private

  def resolve_tenant(tenant_id:, triggered_by_id:)
    Tenant.find_by(id: tenant_id) ||
      AdminUser.find_by(id: triggered_by_id)&.tenant
  end

  def resolve_triggered_by(tenant:, triggered_by_id:)
    return nil if triggered_by_id.blank?

    tenant.admin_users.find_by(id: triggered_by_id)
  end
end
