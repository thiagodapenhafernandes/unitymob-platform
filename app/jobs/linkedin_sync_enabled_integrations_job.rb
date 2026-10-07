class LinkedinSyncEnabledIntegrationsJob < ApplicationJob
  queue_as :sync

  def perform
    LinkedinIntegration.where("token_expires_at > ?", Time.current).find_each do |integration|
      LinkedinSyncJob.perform_later(integration.id)
    end
  end
end
