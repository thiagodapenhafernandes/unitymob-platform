module Whatsapp
  class CampaignProcessorJob < ApplicationJob
    queue_as :default

    def perform(campaign_id)
      campaign = WhatsappCampaign.find_by(id: campaign_id)
      return unless campaign&.processing?

      Whatsapp::CampaignProcessorService.call(campaign)
    end
  end
end
