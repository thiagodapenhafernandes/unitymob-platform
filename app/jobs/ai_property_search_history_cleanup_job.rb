class AiPropertySearchHistoryCleanupJob < ApplicationJob
  queue_as :default

  def perform(tenant_id)
    tenant = Tenant.find_by(id: tenant_id)
    return unless tenant

    setting = PropertySetting.instance(tenant: tenant)
    cutoff = setting.ai_property_search_history_retention_days.days.ago
    AiPropertySearchHistory.where(tenant_id: tenant.id).where("created_at < ?", cutoff).delete_all
    AiPropertyShareAuditEvent.where(tenant_id: tenant.id).where("created_at < ?", cutoff).delete_all
  end
end
