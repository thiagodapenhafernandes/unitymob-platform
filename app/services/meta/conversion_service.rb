module Meta
  # Envia um evento de funil ao Dataset da conta via Conversions API.
  # user_data segue a spec da Meta (normalizado + SHA256); o matching é por
  # ID original do lead ou e-mail/telefone — sem identificador o evento é descartado, pois a Meta
  # não conseguiria atribuir. Nunca registra PII em claro nos logs.
  class ConversionService
    class ConversionError < StandardError; end

    def initialize(config)
      @config = config
    end

    # Envia para todos os datasets configurados (mesmo event_id: a Meta
    # dedupa por dataset). Falha em qualquer um aborta com retry; o event_id
    # estável evita duplicar nos que já receberam.
    def send_event(lead:, event_name:, event_id:, occurred_at:, value: nil)
      user_data = build_user_data(lead)
      if user_data.values_at("em", "ph", "lead_id").all?(&:blank?)
        Rails.logger.info("[Meta::ConversionService] lead_id=#{lead.id} event=#{event_name} skipped_sem_match")
        return :skipped
      end

      event = {
        "event_name" => event_name,
        "event_time" => occurred_at.to_i,
        "event_id" => event_id,
        "action_source" => "system_generated",
        "user_data" => user_data,
        "custom_data" => build_custom_data(event_name, value)
      }.compact

      @config.dataset_list.each do |dataset|
        payload = { "data" => [event] }
        payload["test_event_code"] = @config.test_event_code if @config.test_event_code.present?

        begin
          response = graph.graph_call("#{dataset["id"]}/events", payload, "post")
          Rails.logger.info("[Meta::ConversionService] lead_id=#{lead.id} event=#{event_name} " \
                            "dataset=#{dataset["id"]} received=#{response&.dig("events_received")} " \
                            "trace=#{response&.dig("fbtrace_id")}")
        rescue Koala::Facebook::APIError => e
          raise ConversionError, "CAPI #{event_name} lead_id=#{lead.id} dataset=#{dataset["id"]}: #{e.fb_error_code} #{e.fb_error_type}"
        end
      end

      :sent
    end

    private

    def graph
      @graph ||= Koala::Facebook::API.new(@config.sending_token)
    end

    def build_user_data(lead)
      email = lead.display_email.to_s.strip.downcase
      phone = Phones::Normalizer.call(lead.display_phone).to_s.gsub(/\D/, "")
      first_name, *rest = lead.display_name.to_s.split
      info = lead.other_information.to_h
      lead_id = [info["meta_leadgen_id"],
                 info.dig("facebook_attributes", "leadgen_id"),
                 info.dig("external_lead_payload", "facebook_attributes", "leadgen_id"),
                 info.dig("data", "facebook_attributes", "leadgen_id"),
                 lead.attribution_data.to_h.dig("facebook", "leadgen_id")].find(&:present?)
      {
        "lead_id" => lead_id.presence&.to_s,
        "em" => sha256(email),
        "ph" => sha256(phone),
        "fn" => sha256(first_name&.downcase),
        "ln" => sha256(rest.join(" ").presence&.downcase)
      }.compact
    end

    def build_custom_data(event_name, value)
      data = { "event_source" => "crm", "lead_event_source" => "Unitymob" }
      data.merge!("value" => value.to_f.round(2), "currency" => "BRL") if event_name == "Purchase" && value.to_f.positive?
      data
    end

    def sha256(value)
      return nil if value.blank?

      Digest::SHA256.hexdigest(value)
    end
  end
end
