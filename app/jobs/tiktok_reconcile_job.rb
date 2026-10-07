class TiktokReconcileJob < ApplicationJob
  queue_as :sync

  def perform
    return unless TiktokIntegration.configured?
    TiktokIntegration.where.not(access_token: nil).find_each { |integration| TiktokSyncJob.perform_later(integration.id) }
  end
end
