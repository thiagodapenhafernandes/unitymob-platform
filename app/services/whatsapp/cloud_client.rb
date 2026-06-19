module Whatsapp
  # Cliente da WhatsApp Cloud API (Graph) para enviar mensagens e sincronizar templates.
  # Reusa as credenciais de WhatsappBusinessIntegration.current (waba_id, phone_number_id, access_token).
  class CloudClient
    GRAPH_HOST = "https://graph.facebook.com".freeze

    def self.api_version
      ENV["WHATSAPP_GRAPH_API_VERSION"].presence || ENV["META_API_VERSION"].presence || "v24.0"
    end

    def initialize(integration = WhatsappBusinessIntegration.current)
      @integration = integration
    end

    def configured?
      @integration&.access_token.present? && @integration&.phone_number_id.present?
    end

    def send_text(to:, body:)
      post_message(to: to, type: "text", text: { preview_url: true, body: body.to_s })
    end

    def send_template(to:, name:, language: "pt_BR", components: [])
      template = { name: name, language: { code: language } }
      template[:components] = components if components.present?
      post_message(to: to, type: "template", template: template)
    end

    # Health check de envio: consulta o número na Cloud API (valida token + phone_number_id).
    def phone_info
      return error_result("Integração não configurada") unless configured?

      url = "#{base}/#{@integration.phone_number_id}"
      fields = "verified_name,display_phone_number,quality_rating,code_verification_status,platform_type"
      parse(HTTParty.get(url, query: { access_token: token, fields: fields }, timeout: 15))
    rescue => e
      error_result(e.message)
    end

    # Health check de recebimento: lista apps inscritos no webhook da WABA.
    def subscribed_apps
      return error_result("WABA ID não informado") if @integration.waba_id.blank?
      return error_result("Integração não configurada") unless configured?

      url = "#{base}/#{@integration.waba_id}/subscribed_apps"
      parse(HTTParty.get(url, query: { access_token: token }, timeout: 15))
    rescue => e
      error_result(e.message)
    end

    def fetch_templates
      return error_result("Integração não configurada") unless configured? && @integration.waba_id.present?

      url = "#{base}/#{@integration.waba_id}/message_templates"
      response = HTTParty.get(url, query: { access_token: token, limit: 200 }, timeout: 15)
      parse(response)
    rescue => e
      error_result(e.message)
    end

    private

    def post_message(to:, **payload)
      return error_result("Integração não configurada") unless configured?

      url = "#{base}/#{@integration.phone_number_id}/messages"
      body = { messaging_product: "whatsapp", recipient_type: "individual", to: normalize(to) }.merge(payload)
      response = HTTParty.post(url, headers: auth_headers, body: body.to_json, timeout: 15)
      parse(response)
    rescue => e
      error_result(e.message)
    end

    def base
      "#{GRAPH_HOST}/#{self.class.api_version}"
    end

    def token
      @integration.access_token
    end

    def auth_headers
      { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
    end

    def normalize(phone)
      digits = phone.to_s.gsub(/\D/, "")
      digits.length <= 11 ? "55#{digits}" : digits
    end

    def parse(response)
      data = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        {}
      end
      if response.success?
        { ok: true, status: response.code, data: data, message_id: data.dig("messages", 0, "id") }
      else
        { ok: false, status: response.code, data: data, error: data.dig("error", "message") || "Erro #{response.code}" }
      end
    end

    def error_result(message)
      { ok: false, status: 0, data: {}, error: message }
    end
  end
end
