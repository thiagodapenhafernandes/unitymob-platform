module Webhooks
  class MetaController < ApplicationController
    skip_before_action :verify_authenticity_token

    def receive_leads
      # 1. Verificar Token de Validação (Webhook Challenge) - GET Request
      if request.get? && params["hub.mode"] == "subscribe" && params["hub.verify_token"] == Setting.get("facebook_webhook_verify_token", ENV["FACEBOOK_WEBHOOK_VERIFY_TOKEN"])
        render plain: params["hub.challenge"]
        return
      end

      # 2. Processar Lead Notification - POST Request
      if request.post?
        payload = params.require(:entry)

        payload.each do |entry|
          next unless entry["changes"]
          entry["changes"].each do |change|
            next unless change["field"] == "leadgen"

            lead_data = change["value"]
            if lead_data["leadgen_id"]
              MetaLeadProcessingJob.perform_later(lead_data["leadgen_id"], lead_data["page_id"], lead_data["form_id"])
            end
          end
        end

        head :ok
      end
    rescue => e
      Rails.logger.error "Meta Webhook Error: #{e.message}"
      head :unprocessable_entity
    end
  end
end
