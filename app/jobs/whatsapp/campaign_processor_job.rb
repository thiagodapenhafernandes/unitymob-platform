module Whatsapp
  class CampaignProcessorJob < ApplicationJob
    queue_as :default

    def perform(campaign_id, tenant_id: nil)
      campaign = campaign_scope(tenant_id).find_by(id: campaign_id)
      return unless campaign&.processing?

      Current.set(tenant: campaign.tenant) do
        Whatsapp::CampaignProcessorService.call(campaign)
      end
    end

    private

    def campaign_scope(tenant_id)
      return WhatsappCampaign.all if tenant_id.blank?

      tenant = Tenant.find_by(id: tenant_id)
      tenant ? tenant.whatsapp_campaigns : WhatsappCampaign.none
    end
  end
end
