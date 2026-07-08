module Whatsapp
  class CampaignMessageRetryJob < ApplicationJob
    queue_as :campaigns

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
      # fail-closed: sem tenant o job no-opa (e avisa) em vez de operar
      # cross-tenant. O dispatch sempre passa tenant_id.
      if tenant_id.blank?
        Rails.logger.warn("[WhatsappCampaignMessage] job sem tenant_id — ignorado")
        return WhatsappCampaignMessage.none
      end

      tenant = Tenant.find_by(id: tenant_id)
      tenant ? tenant.whatsapp_campaign_messages : WhatsappCampaignMessage.none
    end
  end
end
