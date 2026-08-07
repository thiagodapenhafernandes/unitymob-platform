module ExternalLeadMigration
  class SyncEnabledIntegrationsJob < ApplicationJob
    queue_as :sync

    def perform
      ExternalLeadIntegration.enabled.find_each do |integration|
        ExternalLeadMigration::IncrementalSyncJob.perform_later(integration.id)
      end
    end
  end
end
