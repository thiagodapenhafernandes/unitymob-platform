module ChavesNaMao
  class ReceiveLead
    PURPOSES = { "Venda" => "venda", "Locação" => "locacao", "Venda/Locação" => "ambos" }.freeze

    def self.call(receipt)
      return unless receipt.status == "pending"

      connection = receipt.chaves_na_mao_connection
      return receipt.quarantine!("receiving_disabled") unless connection.receiving? && connection.operational?

      entry = JSON.parse(receipt.payload)
      ad = entry["ad"]
      unless entry["id"] == receipt.event_id && entry["segment"] == "REALTY" && ad.is_a?(Hash) &&
          %w[id title purpose].all? { |key| ad[key].is_a?(String) && ad[key].present? } &&
          PURPOSES.key?(ad["purpose"]) && entry["name"].is_a?(String) && entry["name"].present? &&
          [entry["email"], entry["phone"], entry["message"], entry["createdAt"], entry["proposeTypeName"], ad["reference"]].all? { |value| value.nil? || value.is_a?(String) }
        return receipt.quarantine!("invalid_payload")
      end
      phone = Phones::Normalizer.call(entry["phone"])
      email = entry["email"].to_s.strip
      return receipt.quarantine!("missing_contact") if phone.blank? && !email.match?(URI::MailTo::EMAIL_REGEXP)

      tenant = connection.tenant
      Current.set(tenant: tenant) do
        properties = tenant.habitations.where(codigo: ad["reference"]).limit(2).to_a if ad["reference"].present?
        return receipt.quarantine!("ambiguous_listing") if properties && properties.size > 1

        property = properties&.first
        business_type = ad["purpose"] == "Locação" && property&.daily_rental? ? "diaria" : PURPOSES.fetch(ad["purpose"])
        receipt.transaction(requires_new: true) do
          lead = Leads::Intake.create!(tenant: tenant, name: entry["name"], client_name: entry["name"],
            phone: phone, client_phone: phone, email: email, client_email: email,
            origin: "Chaves na Mão", attribution_channel: "portal", attribution_source: "chaves_na_mao",
            attribution_data: { "provider" => "chaves_na_mao_direct", "business_type" => business_type },
            property_id: property&.id, product: property&.display_title || ad["title"],
            notes: ["Contato recebido pelo Chaves na Mão", "ID do anúncio: #{ad['id']}",
              ("Referência do imóvel: #{ad['reference']}" if ad["reference"].present?), entry["message"].presence].compact.join("\n"),
            other_information: { "chaves_na_mao_event_id" => "#{connection.route_key}:#{receipt.event_id}",
              "business_type" => business_type, "origin_listing_id" => ad["id"],
              "origin_listing_reference" => ad["reference"], "portal_message" => entry["message"],
              "propose_type_name" => entry["proposeTypeName"], "portal_created_at" => entry["createdAt"] })
          lead.property_interests.find_or_create_by!(habitation: property) { |interest| interest.tenant = tenant } if property
          receipt.update!(lead: lead, status: "processed", reason: nil, processed_at: Time.current)
          connection.update!(last_lead_received_at: Time.current)
        end
      end
    rescue ActiveRecord::RecordInvalid
      receipt.reload.quarantine!("invalid_lead")
    end
  end
end
