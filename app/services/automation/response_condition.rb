module Automation
  # Interpretação compartilhada; cada consumidor mantém seu contexto de execução.
  class ResponseCondition
    # O dispatcher pode consultar a mensagem no banco; resolver o corpo só no fallback.
    def initialize(payload:, lead:, &body)
      @payload = (payload || {}).with_indifferent_access
      @body = body
      @lead = lead
    end

    def matches?(condition)
      condition = (condition || {}).with_indifferent_access
      return button_payload_or_text_condition_matches?(condition) if condition[:match_strategy].to_s == "button_payload_or_text"

      value = value_for(condition[:field])
      expected = condition[:value].to_s.strip

      case condition[:operator].to_s
      when "present"
        value.present?
      when "not_contains"
        expected.blank? || !value.to_s.downcase.include?(expected.downcase)
      when "contains"
        expected.blank? || value.to_s.downcase.include?(expected.downcase)
      else
        value.to_s.casecmp?(expected)
      end
    end

    private

    def button_payload_or_text_condition_matches?(condition)
      expected_payload = condition[:button_payload].presence || condition[:button_key].presence || condition[:value].presence
      expected_text = condition[:button_text].presence || condition[:fallback_value].presence
      payload_value = value_for("interaction.button_payload")
      text_value = value_for("interaction.button_text")

      (expected_payload.present? && payload_value.to_s.casecmp?(expected_payload.to_s)) ||
        (expected_text.present? && text_value.to_s.casecmp?(expected_text.to_s))
    end

    def value_for(field)
      payload = @payload
      case field.to_s
      when "message.body"
        @body.call
      when "interaction.button_text"
        payload.dig(:button, :title).presence ||
          payload.dig(:interactive, :button_reply, :title).presence ||
          payload[:button_text].presence ||
          @body.call
      when "interaction.button_payload"
        payload.dig(:button, :id).presence ||
          payload.dig(:interactive, :button_reply, :id).presence ||
          payload[:button_payload].presence ||
          payload[:button_id]
      when "campaign.response_decision.action"
        payload.dig(:response_decision, :action)
      when "campaign.response_decision.label"
        payload.dig(:response_decision, :action_label)
      when "campaign.response_decision.distribution_rule_id"
        payload.dig(:response_decision, :distribution_rule_id)
      when "lead.status", "lead.lifecycle"
        @lead&.status
      when "guardrail.outside_hours"
        payload[:outside_hours]
      when "guardrail.crm_error"
        payload[:crm_error]
      else
        payload.dig(*field.to_s.split(".").map(&:to_sym))
      end
    end
  end
end
