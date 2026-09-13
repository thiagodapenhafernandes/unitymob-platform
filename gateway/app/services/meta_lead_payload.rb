# frozen_string_literal: true

module Gateway
  module MetaLeadPayload
    module_function

    def extract_event_contexts(payload)
      if payload["object"] == "instagram"
        return Array(payload["entry"]).flat_map do |entry|
          Array(entry["messaging"]).map do |event|
            { external_id: event.dig("message", "mid"), event_type: "instagram", page_id: entry["id"], form_id: nil, payload: {"object" => "instagram", "entry" => [{"id" => entry["id"], "messaging" => [event]}]} }
          end
        end
      end
      contexts = Array(payload["entry"]).flat_map do |entry|
        Array(entry["changes"]).filter_map do |change|
          next unless change["field"].to_s == "leadgen"

          value = change.fetch("value", {})
          leadgen_id = value["leadgen_id"].to_s
          page_id = value["page_id"].to_s
          form_id = value["form_id"].to_s
          next if leadgen_id.empty? && page_id.empty? && form_id.empty?

          {
            external_id: leadgen_id,
            event_type: "leadgen",
            page_id:,
            form_id:,
            payload: {"object" => payload["object"], "entry" => [entry.slice("id", "time").merge("changes" => [change])]}
          }
        end
      end

      contexts.empty? ? [fallback_context(payload)] : contexts
    end

    def fallback_context(payload)
      {
        external_id: nil,
        event_type: payload["object"].to_s.empty? ? "unknown" : payload["object"].to_s,
        page_id: nil,
        form_id: nil
      }
    end
  end
end
