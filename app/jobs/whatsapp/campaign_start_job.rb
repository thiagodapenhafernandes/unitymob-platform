module Whatsapp
  class CampaignStartJob < ApplicationJob
    queue_as :default

    def perform(campaign_id, tenant_id: nil)
      campaign = campaign_scope(tenant_id).find_by(id: campaign_id)
      return unless campaign&.scheduled?
      return if campaign.scheduled_at.present? && campaign.scheduled_at.future?

      Current.set(tenant: campaign.tenant) do
        campaign.start!
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
