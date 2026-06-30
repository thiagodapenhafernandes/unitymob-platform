module Whatsapp
  class CampaignMessageRetryJob < ApplicationJob
    queue_as :default

    def perform(campaign_message_id, tenant_id: nil)
      campaign_message = campaign_message_scope(tenant_id).find_by(id: campaign_message_id)
      return unless campaign_message&.failed?
      return unless campaign_message.whatsapp_campaign&.tenant_id == campaign_message.tenant_id
      return unless campaign_message.next_retry_at.blank? || campaign_message.next_retry_at <= Time.current
      return unless campaign_message.retry_count.to_i < 3
      return unless campaign_message.whatsapp_campaign.processing?

      Current.set(tenant: campaign_message.tenant) do
        campaign_message.update!(status: "pending", next_retry_at: nil)
        Whatsapp::CampaignMessageDispatchJob.perform_later(campaign_message.id, tenant_id: campaign_message.tenant_id)
      end
    end

    private

    def campaign_message_scope(tenant_id)
      return WhatsappCampaignMessage.all if tenant_id.blank?

      tenant = Tenant.find_by(id: tenant_id)
      tenant ? tenant.whatsapp_campaign_messages : WhatsappCampaignMessage.none
    end
  end
end
