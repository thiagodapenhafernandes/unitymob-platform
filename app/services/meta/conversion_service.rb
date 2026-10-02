module Meta
  # Envia um evento de funil ao Dataset da conta via Conversions API.
  # user_data segue a spec da Meta (normalizado + SHA256); o matching é por
  # e-mail/telefone — sem nenhum dos dois o evento é descartado, pois a Meta
  # não conseguiria atribuir. Nunca registra PII em claro nos logs.
  class ConversionService
    class ConversionError < StandardError; end

    def initialize(config)
      @config = config
    end

    def send_event(lead:, event_name:, event_id:, occurred_at:, value: nil)
      user_data = build_user_data(lead)
      if user_data["em"].blank? && user_data["ph"].blank?
        Rails.logger.info("[Meta::ConversionService] lead_id=#{lead.id} event=#{event_name} skipped_sem_match")
        return :skipped
      end

      payload = {
        "data" => [
          {
            "event_name" => event_name,
            "event_time" => occurred_at.to_i,
            "event_id" => event_id,
            "action_source" => "system_generated",
            "user_data" => user_data,
            "custom_data" => build_custom_data(event_name, value)
          }.compact
        ]
      }
      payload["test_event_code"] = @config.test_event_code if @config.test_event_code.present?

      response = graph.graph_call("#{@config.dataset_id}/events", payload, "post")
      Rails.logger.info("[Meta::ConversionService] lead_id=#{lead.id} event=#{event_name} " \
                        "received=#{response&.dig("events_received")} trace=#{response&.dig("fbtrace_id")}")
      :sent
    rescue Koala::Facebook::APIError => e
      raise ConversionError, "CAPI #{event_name} lead_id=#{lead.id}: #{e.fb_error_code} #{e.fb_error_type}"
    end

    private

    def graph
      @graph ||= Koala::Facebook::API.new(@config.sending_token)
    end

    def build_user_data(lead)
      email = lead.display_email.to_s.strip.downcase
      phone = Phones::Normalizer.call(lead.display_phone).to_s.gsub(/\D/, "")
      first_name, *rest = lead.display_name.to_s.split
      {
        "em" => sha256(email),
        "ph" => sha256(phone),
        "fn" => sha256(first_name&.downcase),
        "ln" => sha256(rest.join(" ").presence&.downcase)
      }.compact
    end

    def build_custom_data(event_name, value)
      return nil unless event_name == "Purchase" && value.to_f.positive?

      { "value" => value.to_f.round(2), "currency" => "BRL" }
    end

    def sha256(value)
      return nil if value.blank?

      Digest::SHA256.hexdigest(value)
    end
  end
end
