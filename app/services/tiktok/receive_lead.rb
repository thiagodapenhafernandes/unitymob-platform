module Tiktok
  class ReceiveLead
    def self.call(integration, entry)
      advertiser_id = entry.fetch("advertiser_id").to_s
      raise Client::Error, "Anunciante não selecionado nesta conexão." unless integration.connected? && integration.selected_account_ids.include?(advertiser_id)
      raise Client::Error, "Origem TikTok não suportada." unless entry["lead_source"].to_s.in?(["", "INSTANT_FORM"])
      external_id = entry.fetch("id").to_s
      form_id = entry.fetch("page_id").to_s
      raise Client::Error, "Lead TikTok sem identificação." if external_id.blank? || form_id.blank?
      fields = entry.fetch("changes").to_h { |change| [change.fetch("field"), change.fetch("value")] }
      name = fields["name"].presence || fields["full_name"].presence || "Lead TikTok"
      phone = fields["phone_number"].presence
      email = fields["email"].presence
      raise Client::Error, "Formulário TikTok sem telefone ou e-mail válido." if phone.blank? && !email.to_s.match?(URI::MailTo::EMAIL_REGEXP)
      Current.set(tenant: integration.tenant) do
        TiktokLeadReceipt.transaction(requires_new: true) do
          receipt = TiktokLeadReceipt.create!(tenant: integration.tenant, advertiser_id: advertiser_id, external_id: external_id)
          lead = Leads::Intake.create!(tenant: integration.tenant, name: name, client_name: name, phone: phone, client_phone: phone, email: email, client_email: email,
            origin: "TikTok Ads", product: entry["page_name"], attribution_channel: "tiktok_ads", attribution_source: "tiktok",
            attribution_data: { "version" => 2, "provider" => "tiktok_lead_generation", "campaign_id" => entry["campaign_id"].to_s,
              "campaign_name" => entry["campaign_name"], "ad_id" => entry["ad_id"].to_s, "ad_name" => entry["ad_name"], "form_id" => form_id },
            other_information: { "tiktok_lead_id" => external_id, "tiktok_advertiser_id" => advertiser_id, "tiktok_form_id" => form_id,
              "tiktok_form_name" => entry["page_name"], "tiktok_answers" => fields, "tiktok_create_time" => entry["create_time"] })
          receipt.update!(lead: lead)
          integration.update!(last_lead_received_at: Time.current)
        end
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
