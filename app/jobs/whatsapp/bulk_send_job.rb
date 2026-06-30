module Whatsapp
  class BulkSendJob < ApplicationJob
    queue_as :default

    def perform(campaign_id, tenant_id: nil)
      campaign = campaign_scope(tenant_id).find_by(id: campaign_id)
      return unless campaign&.processing?

      Current.set(tenant: campaign.tenant) do
        limit = [campaign.send_rate.to_i, 1].max
        messages = campaign.campaign_messages.where(status: "pending").order(:created_at).limit(limit)
        if messages.empty?
          campaign.complete_if_finished!
          return
        end

        messages.each do |message|
          Whatsapp::CampaignMessageDispatchJob.perform_later(message.id, tenant_id: campaign.tenant_id)
        end

        if campaign.reload.processing? && campaign.campaign_messages.where(status: "pending").exists?
          self.class.set(wait: 1.minute).perform_later(campaign.id, tenant_id: campaign.tenant_id)
        end
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
