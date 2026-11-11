module Instagram
  class RoutingContext
    def self.apply(lead)
      return unless lead.instagram_account_id.present? && lead.tenant_id.present?

      page = MetaFacebookPage.available_for_distribution(lead.tenant_id)
        .find_by(instagram_id: lead.instagram_account_id, instagram_enabled: true)
      return unless page

      info = lead.other_information.to_h.deep_dup
      info["meta_page_id"] = page.page_id
      if lead.persisted? && info["business_type"].blank? && info["negotiation_type"].blank?
        lead.instagram_messages.inbound.order(id: :desc).limit(20).each do |message|
          type = CaptureAnswer.new(message.body).business_type
          next unless type

          info["business_type"] = type
          info["instagram_capture"] = info.fetch("instagram_capture", {}).merge("business_type_message_id" => message.id)
          break
        end
      end
      lead.other_information = info
    end
  end
end
