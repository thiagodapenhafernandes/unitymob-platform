module Instagram
  class AdEnrichmentJob < ApplicationJob
    queue_as :sync
    retry_on Koala::Facebook::APIError, wait: :polynomially_longer, attempts: 3

    def perform(tenant_id, lead_id, message_id)
      tenant = Tenant.find_by(id: tenant_id)
      lead = tenant&.leads&.find_by(id: lead_id)
      message = lead&.instagram_messages&.inbound&.find_by(id: message_id)
      return unless message && message.context.to_h["ad_attribution"].blank?

      page = MetaFacebookPage.available_for_distribution(tenant.id).find_by(
        id: message.context.to_h["meta_facebook_page_id"], instagram_id: lead.instagram_account_id, instagram_enabled: true)
      return unless page

      integration = page.user_meta_integration
      return if integration.expired? || integration.access_token.blank? || integration.ad_account_ids.empty?

      referral = message.context.to_h["referral"]
      return unless referral.is_a?(Hash)

      data = Facebook::MetaService.new(integration.access_token).ad_attribution(referral["ad_id"], account_ids: integration.ad_account_ids)
      return unless data

      lead.with_lock do
        message.with_lock do
          return unless lead.tenant_id == tenant.id && message.lead_id == lead.id && message.context.to_h["ad_attribution"].blank?
          return unless message.context.dig("referral", "ad_id") == data["meta_ad_id"] && message.context["meta_facebook_page_id"] == page.id
          return unless MetaFacebookPage.available_for_distribution(tenant.id).exists?(
            id: page.id, instagram_id: lead.instagram_account_id, instagram_enabled: true)
          integration.reload
          return if integration.expired? || integration.access_token.blank? || !integration.ad_account_ids.include?(data["meta_ad_account_id"])

          attribution = data.merge("enriched_at" => Time.current.iso8601)
          message.update_columns(context: message.context.to_h.merge("ad_attribution" => attribution))
          info = lead.other_information.to_h
          entry = info["instagram_entry"]
          # Só complementa a entrada correspondente; campanhas posteriores ficam na própria mensagem.
          if entry.is_a?(Hash) && entry["message_id"] == message.message_id &&
              entry.dig("referral", "ad_id") == referral["ad_id"] && entry["ad_attribution"].blank?
            lead.update_columns(other_information: info.merge("instagram_entry" => entry.merge("ad_attribution" => attribution)))
          end
        end
      end
    end
  end
end
