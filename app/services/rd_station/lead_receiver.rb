module RdStation
  class LeadReceiver
    Result = Struct.new(:lead, :errors, keyword_init: true) do
      def success?
        lead&.persisted?
      end
    end

    ORIGIN = "RD Station".freeze

    class << self
      def call(tenant:, payload:, request: nil)
        new(tenant:, payload:, request:).call
      end
    end

    def initialize(tenant:, payload:, request: nil)
      @tenant = tenant
      @payload = normalize_hash(payload)
      @request = request
    end

    def call
      lead = existing_lead || tenant.leads.new
      lead.assign_attributes(lead_attributes)
      lead.save
      Result.new(lead:, errors: lead.errors.full_messages)
    end

    private

    attr_reader :tenant, :payload, :request

    def lead_attributes
      {
        tenant:,
        name: field_value("name") || field_value("email") || "Lead RD Station",
        email: field_value("email"),
        phone: Phones::Normalizer.call(field_value("mobile_phone", "personal_phone", "phone")),
        lead_type: "rd_station",
        origin: ORIGIN,
        product: product_value,
        source_url: field_value("conversion_url", "url"),
        other_information: existing_information.merge(
          "rd_station_payload" => payload,
          "rd_station_contact_uuid" => field_value("uuid"),
          "rd_station_event_type" => payload["event_type"],
          "rd_station_conversion_identifier" => conversion_identifier,
          "rd_station_campaign_name" => campaign_name,
          "rd_station_source" => rd_source,
          "rd_station_medium" => field_value("utm_medium", "medium"),
          "rd_station_tags" => tags,
          "rd_station_received_at" => Time.current.iso8601,
          "request_ip" => request&.remote_ip
        ).compact
      }.compact
    end

    def existing_lead
      @existing_lead ||= begin
        scope = tenant.leads
        phone = Phones::Normalizer.call(field_value("mobile_phone", "personal_phone", "phone"))
        email = field_value("email")
        by_email = scope.find_by(email:) if email.present?
        by_email || (scope.find_by(phone:) if phone.present?)
      end
    end

    def existing_information
      existing_lead&.other_information.is_a?(Hash) ? existing_lead.other_information : {}
    end

    def contact
      value = payload["contact"] || payload["lead"] || payload["data"]
      value.is_a?(Hash) ? value : payload
    end

    def product_value
      field_value("cf_interesse", "interest", "product") || conversion_identifier
    end

    def conversion_identifier
      field_value("conversion_identifier") || payload["event_identifier"].to_s.presence
    end

    def campaign_name
      field_value("campaign_name", "utm_campaign", "cf_campaign", "cf_campanha")
    end

    def rd_source
      field_value("traffic_source", "source", "utm_source", "cf_origem")
    end

    def tags
      Array.wrap(contact["tags"] || contact["tag_list"])
        .flat_map { |tag| tag.to_s.split(",") }
        .map { |tag| tag.strip }
        .reject(&:blank?)
        .uniq
    end

    def field_value(*keys)
      keys.each do |key|
        value = contact[key] || contact[key.to_sym] || payload[key] || payload[key.to_sym]
        return value.to_s.strip if value.present?
      end
      nil
    end

    def normalize_hash(value)
      if value.respond_to?(:to_unsafe_h)
        value.to_unsafe_h
      elsif value.respond_to?(:to_h)
        value.to_h
      else
        {}
      end
    end
  end
end
