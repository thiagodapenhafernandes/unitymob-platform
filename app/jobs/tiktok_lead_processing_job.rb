class TiktokLeadProcessingJob < ApplicationJob
  self.log_arguments = false
  queue_as :default
  retry_on Tiktok::Client::Error, wait: :polynomially_longer, attempts: 5

  def perform(integration_id, entry)
    integration = TiktokIntegration.find_by(id: integration_id)
    return unless integration
    Current.set(tenant: integration.tenant) do
      integration.with_lock do
        return unless integration.connected? && integration.selected_account_ids.include?(entry["advertiser_id"].to_s)
        Tiktok::ReceiveLead.call(integration, entry)
      end
    end
  rescue StandardError => error
    integration&.update_columns(last_error: "Não foi possível processar um lead TikTok. Contate o suporte para revisar os campos do formulário.")
    Rails.logger.warn("[TiktokLeadProcessing] integration_id=#{integration_id} error=#{error.class}")
    raise
  end
end
