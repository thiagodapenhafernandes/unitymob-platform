class ResetSyncStatusJob < ApplicationJob
  queue_as :default

  def perform(integration_id)
    integration = UserMetaIntegration.find_by(id: integration_id)
    return unless integration
    
    integration.update!(sync_status: nil, sync_progress: 0, sync_message: nil)
    
    Turbo::StreamsChannel.broadcast_replace_to(
      "meta_sync_#{integration.id}",
      target: "meta_sync_status",
      partial: "admin/meta_integrations/sync_status",
      locals: { integration: integration }
    )
  end
end
