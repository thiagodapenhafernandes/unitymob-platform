module Whatsapp
  class CampaignMessageDispatchJob < ApplicationJob
    queue_as :default

    def perform(campaign_message_id)
      campaign_message = WhatsappCampaignMessage.includes(:whatsapp_campaign, :lead, :whatsapp_campaign_recipient).find_by(id: campaign_message_id)
      return unless campaign_message
      return unless campaign_message.whatsapp_campaign.processing?
      return unless campaign_message.pending? || campaign_message.queued?

      Whatsapp::CampaignMessageSender.call(campaign_message)
      campaign_message.whatsapp_campaign.complete_if_finished!
    end
  end
end
