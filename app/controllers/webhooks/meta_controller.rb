module Webhooks
  # Herda de ActionController::Base (não de ApplicationController) para não
  # executar o pipeline público (SEO redirect, tenant público) no webhook —
  # mesmo padrão do Webhooks::WhatsappController.
  class MetaController < ActionController::Base
    include Webhooks::MetaSignature

    skip_forgery_protection

    def receive_leads
      # 1. Verificar Token de Validação (Webhook Challenge) - GET Request
      if request.get? && params["hub.mode"] == "subscribe" && params["hub.verify_token"] == Setting.get("facebook_webhook_verify_token", ENV["FACEBOOK_WEBHOOK_VERIFY_TOKEN"])
        render plain: params["hub.challenge"]
        return
      end

      # 2. Processar Lead Notification - POST Request
      if request.post?
        unless valid_meta_signature?(request.raw_post.to_s)
          Rails.logger.warn "Meta Webhook: assinatura X-Hub-Signature-256 invalida; payload rejeitado"
          return head :forbidden
        end

        Array(params[:entry]).each do |entry|
          Array(entry["changes"]).each do |change|
            next unless change["field"] == "leadgen"

            lead_data = change["value"]
            next if lead_data.blank?

            if lead_data["leadgen_id"]
              MetaLeadProcessingJob.perform_later(lead_data["leadgen_id"], lead_data["page_id"], lead_data["form_id"])
            end
          end
        end

        head :ok
      end
    rescue => e
      Rails.logger.error "Meta Webhook Error: #{e.class}: #{e.message}\n#{Array(e.backtrace).first(10).join("\n")}"
      head :ok # não-2xx faz a Meta reentregar em loop e pode desativar a subscription; o retry real fica no job
    end
  end
end
