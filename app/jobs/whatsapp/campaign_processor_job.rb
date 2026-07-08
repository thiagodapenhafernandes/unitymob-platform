module Whatsapp
  class CampaignProcessorJob < ApplicationJob
    queue_as :campaigns

    def perform(campaign_id, tenant_id: nil)
      campaign = campaign_scope(tenant_id).find_by(id: campaign_id)
      return unless campaign&.processing?

      Current.set(tenant: campaign.tenant) do
        Whatsapp::CampaignProcessorService.call(campaign)
      end
    end

    private

    def campaign_scope(tenant_id)
      # fail-closed: sem tenant o job no-opa (e avisa) em vez de operar
      # cross-tenant. O dispatch sempre passa tenant_id.
      if tenant_id.blank?
        Rails.logger.warn("[WhatsappCampaign] job sem tenant_id — ignorado")
        return WhatsappCampaign.none
      end

      tenant = Tenant.find_by(id: tenant_id)
      tenant ? tenant.whatsapp_campaigns : WhatsappCampaign.none
    end
  end
end
