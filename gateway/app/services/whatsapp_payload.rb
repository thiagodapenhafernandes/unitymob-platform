# frozen_string_literal: true

module Gateway
  module WhatsappPayload
    module_function

    def extract_event_contexts(payload)
      entries = Array(payload["entry"])
      contexts = entries.flat_map do |entry|
        Array(entry["changes"]).flat_map do |change|
          value = change.fetch("value", {})
          metadata = value.fetch("metadata", {})
          waba_id = entry["id"].to_s
          phone_number_id = metadata["phone_number_id"].to_s

          message_contexts(value, waba_id:, phone_number_id:) +
            status_contexts(value, waba_id:, phone_number_id:) +
            template_status_contexts(change, value, waba_id:, phone_number_id:)
        end
      end

      contexts.empty? ? [fallback_context(payload)] : contexts
    end

    def message_contexts(value, waba_id:, phone_number_id:)
      Array(value["messages"]).map do |message|
        {
          external_id: message["id"].to_s,
          event_type: "message",
          waba_id:,
          phone_number_id:
        }
      end
    end

    def status_contexts(value, waba_id:, phone_number_id:)
      Array(value["statuses"]).map do |status|
        {
          external_id: status["id"].to_s,
          event_type: "status",
          waba_id:,
          phone_number_id:
        }
      end
    end

    def template_status_contexts(change, value, waba_id:, phone_number_id:)
      return [] unless change["field"].to_s == "message_template_status_update"

      [
        {
          external_id: value["message_template_id"].to_s,
          event_type: "message_template_status_update",
          waba_id:,
          phone_number_id:
        }
      ]
    end

    def fallback_context(payload)
      {
        external_id: nil,
        event_type: payload["object"].to_s.empty? ? "unknown" : payload["object"].to_s,
        waba_id: nil,
        phone_number_id: nil
      }
    end
  end
end
