module Portal
  class WebhookParser
    def initialize(portal:, payload:)
      @portal = portal
      @payload = payload.is_a?(Hash) ? payload : {}
    end

    def events
      if @payload["events"].is_a?(Array)
        @payload["events"].map { |item| normalize(item) }.compact
      else
        [normalize(@payload)].compact
      end
    end

    private

    def normalize(item)
      data = item.is_a?(Hash) ? item : {}
      event_type = data["event"].presence || data["event_type"].presence || data["status"].presence || "updated"
      external_listing_id = data["listing_id"].presence || data["external_id"].presence || data["ad_id"].presence || data["id"].presence
      habitation_code = data["habitation_code"].presence || data["codigo"].presence || data.dig("listing", "reference")
      normalized_status = data["status"].presence || event_type

      {
        portal: @portal,
        event_type: event_type.to_s,
        normalized_status: normalized_status.to_s,
        external_listing_id: external_listing_id.to_s.presence,
        habitation_code: habitation_code.to_s.presence,
        raw_payload: data
      }
    end
  end
end
