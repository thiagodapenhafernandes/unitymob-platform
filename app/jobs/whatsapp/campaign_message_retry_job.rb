module Whatsapp
  class CampaignMessageRetryJob < ApplicationJob
    queue_as :default

    def perform(campaign_message_id)
      campaign_message = WhatsappCampaignMessage.find_by(id: campaign_message_id)
      return unless campaign_message&.failed?
      return unless campaign_message.next_retry_at.blank? || campaign_message.next_retry_at <= Time.current
      return unless campaign_message.retry_count.to_i < 3
      return unless campaign_message.whatsapp_campaign.processing?

      campaign_message.update!(status: "pending", next_retry_at: nil)
      Whatsapp::CampaignMessageDispatchJob.perform_later(campaign_message.id)
    end
  end
end
