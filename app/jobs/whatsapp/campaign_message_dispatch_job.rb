module Whatsapp
  class CampaignMessageDispatchJob < ApplicationJob
    queue_as :campaigns

    def perform(campaign_message_id, tenant_id: nil)
      campaign_message = campaign_message_scope(tenant_id)
        .includes(:whatsapp_campaign, :lead, :whatsapp_campaign_recipient)
        .find_by(id: campaign_message_id)
      return unless campaign_message
      return unless tenant_consistent?(campaign_message)
      return unless campaign_message.whatsapp_campaign.processing?

      Current.set(tenant: campaign_message.tenant) do
        should_send = false
        campaign_message.with_lock do
          campaign_message.reload
          return unless campaign_message.whatsapp_campaign.processing?
          return unless campaign_message.pending?

          campaign_message.queue!
          should_send = true
        end
        return unless should_send

        Whatsapp::CampaignMessageSender.call(campaign_message)
        campaign_message.whatsapp_campaign.complete_if_finished!
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

    def tenant_consistent?(campaign_message)
      tenant_id = campaign_message.tenant_id
      tenant_id.present? &&
        campaign_message.whatsapp_campaign&.tenant_id == tenant_id &&
        (campaign_message.lead.blank? || campaign_message.lead.tenant_id == tenant_id) &&
        (campaign_message.whatsapp_campaign_recipient.blank? || campaign_message.whatsapp_campaign_recipient.tenant_id == tenant_id)
    end
  end
end
