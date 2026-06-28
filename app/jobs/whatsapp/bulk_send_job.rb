module Whatsapp
  class BulkSendJob < ApplicationJob
    queue_as :default

    def perform(campaign_id)
      campaign = WhatsappCampaign.find_by(id: campaign_id)
      return unless campaign&.processing?

      limit = [campaign.send_rate.to_i, 1].max
      messages = campaign.campaign_messages.pending_or_queued.order(:created_at).limit(limit)
      return campaign.complete_if_finished! if messages.empty?

      messages.each do |message|
        Whatsapp::CampaignMessageDispatchJob.perform_later(message.id)
      end

      if campaign.reload.processing? && campaign.campaign_messages.pending_or_queued.exists?
        self.class.set(wait: 1.minute).perform_later(campaign.id)
      end
    end
  end
end
