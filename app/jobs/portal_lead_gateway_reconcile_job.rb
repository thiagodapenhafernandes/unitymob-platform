class PortalLeadGatewayReconcileJob < ApplicationJob
  queue_as :sync

  def perform
    return unless Portal::LeadGatewayClient.configured?

    PortalIntegration.where(portal: PortalIntegration::GRUPOZAP_PORTALS).find_each do |integration|
      PortalLeadGatewaySyncJob.perform_later(integration.id)
    end
  end
end
