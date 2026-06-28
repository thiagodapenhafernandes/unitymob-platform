module Whatsapp
  class CampaignStartJob < ApplicationJob
    queue_as :default

    def perform(campaign_id)
      campaign = WhatsappCampaign.find_by(id: campaign_id)
      return unless campaign&.scheduled?
      return if campaign.scheduled_at.present? && campaign.scheduled_at.future?

      campaign.start!
    end
  end
end
