# Agendado pelo config/recurring.yml: um MetaInsightsSyncJob por tenant com
# integração Meta e conta de anúncios selecionada.
class MetaInsightsSyncAllTenantsJob < ApplicationJob
  queue_as :sync

  def perform
    Tenant.active.find_each do |tenant|
      next unless insights_configured_for?(tenant)

      MetaInsightsSyncJob.perform_later(tenant.id)
    end
  end

  private

  def insights_configured_for?(tenant)
    UserMetaIntegration.owned_by_tenant(tenant.id).where.not(access_token: [nil, ""]).any? do |integration|
      integration.ad_account_ids.any?
    end
  end
end
