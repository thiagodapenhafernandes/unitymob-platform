module Imovelweb
  class ReceiveLead
    FIELDS = %w[event_id event_type client_code environment reference listing_id name email phone message registered_at contact_type message_id lead_origin].freeze

    def self.valid_payload?(entry)
      entry.is_a?(Hash) && entry.keys.all? { |key| FIELDS.include?(key) } &&
        entry.values.all? { |value| value.nil? || value.is_a?(String) } &&
        %w[event_id client_code environment].all? { |key| entry[key].present? && entry[key].bytesize <= 255 } &&
        entry["event_type"].in?(%w[CONTACTO CONTACTO_MENSAJE])
    end

    def self.call(receipt)
      connection = receipt.imovelweb_connection
      return unless connection.receiving? && receipt.status == "pending"
      entry = JSON.parse(receipt.payload)
      unless valid_payload?(entry) && entry["client_code"] == connection.client_code && entry["environment"] == connection.environment
        return receipt.quarantine!("invalid_payload")
      end
      tenant = connection.tenant
      Current.set(tenant: tenant) do
        listing = connection.imovelweb_listings.find_by(reference: entry["reference"]) if entry["reference"].present?
        external_listing = connection.imovelweb_listings.find_by(external_id: entry["listing_id"]) if entry["listing_id"].present?
        if listing && external_listing && listing.id != external_listing.id
          return receipt.quarantine!("conflicting_listing")
        end
        listing ||= external_listing
        return receipt.quarantine!("unknown_listing") unless listing && listing.habitation.tenant_id == tenant.id
        phone = Phones::Normalizer.call(entry["phone"])
        email = entry["email"].to_s.strip
        return receipt.quarantine!("missing_contact") if phone.blank? && !email.match?(URI::MailTo::EMAIL_REGEXP)

        receipt.transaction(requires_new: true) do
          property = listing.habitation
          name = entry["name"].presence || "Lead Imovelweb"
          lead = Leads::Intake.create!(tenant: tenant, name: name, client_name: name,
            phone: phone, client_phone: phone, email: email, client_email: email,
            origin: "Imovelweb", attribution_channel: "portal", attribution_source: "imovelweb",
            attribution_data: { "provider" => "imovelweb_direct", "event_type" => entry["event_type"],
              "client_code" => connection.client_code, "listing_id" => entry["listing_id"], "contact_type" => entry["contact_type"] },
            product: property.display_title, property_id: property.id,
            other_information: { "imovelweb_event_id" => "#{connection.route_key}:#{receipt.event_id}",
              "lead_origin" => "Imovelweb", "origin_listing_id" => entry["listing_id"],
              "portal_message" => entry["message"], "imovelweb_registered_at" => entry["registered_at"], "imovelweb_message_id" => entry["message_id"] })
          lead.property_interests.find_or_create_by!(habitation: property) { |interest| interest.tenant = tenant }
          receipt.update!(lead: lead, status: "processed", reason: nil, processed_at: Time.current)
          connection.update!(last_lead_received_at: Time.current)
        end
      end
    rescue ActiveRecord::RecordInvalid
      # Clear rolled-back associations so autosave cannot recreate the failed lead.
      receipt.reload.quarantine!("invalid_lead")
    end
  end
end
