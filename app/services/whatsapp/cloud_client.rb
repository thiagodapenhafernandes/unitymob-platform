module Whatsapp
  # Cliente da WhatsApp Cloud API (Graph) para enviar mensagens e sincronizar templates.
  # Reusa as credenciais de WhatsappBusinessIntegration.current (waba_id, phone_number_id, access_token).
  #
  # Aceita QUALQUER objeto que responda a essa interface (duck-typing):
  #   access_token, phone_number_id e (para templates) waba_id. Além da
  #   WhatsappBusinessIntegration do tenant, isso inclui o sender GLOBAL de
  #   Notifications::TransportResolver (GlobalWhatsappSender), usado no fallback
  #   global do Admin do Sistema — envio de texto/template funciona igual.
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

    def send_text(to:, body:, context_message_id: nil)
      payload = { type: "text", text: { preview_url: true, body: body.to_s } }
      payload[:context] = { message_id: context_message_id } if context_message_id.present?
      post_message(to: to, **payload)
    end

    # Reação a uma mensagem (emoji vazio remove a reação)
    def send_reaction(to:, message_id:, emoji:)
      post_message(to: to, type: "reaction", reaction: { message_id: message_id, emoji: emoji.to_s })
    end

    def send_template(to:, name:, language: "pt_BR", components: [])
      template = { name: name, language: { code: language } }
      template[:components] = components if components.present?
      post_message(to: to, type: "template", template: template)
    end

    def send_media(to:, type:, media_id: nil, link: nil, caption: nil, filename: nil, context_message_id: nil)
      media_type = type.to_s.presence || "image"
      media_payload = {}
      media_payload[:id] = media_id if media_id.present?
      media_payload[:link] = link if link.present?
      media_payload[:caption] = caption if caption.present? && media_type != "audio"
      media_payload[:filename] = filename if filename.present? && media_type == "document"

      payload = { type: media_type, media_type.to_sym => media_payload }
      payload[:context] = { message_id: context_message_id } if context_message_id.present?
      post_message(to: to, **payload)
    end

    def upload_message_media(file_name:, content_type:, type:, io:)
      return error_result("Integração não configurada") unless configured?

      require "faraday/multipart"

      io.rewind if io.respond_to?(:rewind)
      response = Faraday.new(url: base) do |faraday|
        faraday.request :multipart
        faraday.request :url_encoded
        # Timeouts explícitos (default do Net::HTTP é 60s renovável por pacote):
        # alinhado ao timeout: 60 do upload de template media abaixo.
        faraday.options.open_timeout = 10
        faraday.options.timeout = 120
        faraday.adapter Faraday.default_adapter
      end.post("#{@integration.phone_number_id}/media") do |request|
        request.headers["Authorization"] = "Bearer #{token}"
        request.body = {
          messaging_product: "whatsapp",
          type: type.to_s.presence || "image",
          file: Faraday::Multipart::FilePart.new(io.path, content_type.to_s.presence || "application/octet-stream", file_name.to_s.presence || "media")
        }
      end

      result = parse(response)
      return result unless result[:ok]

      media_id = result.dig(:data, "id").presence
      return error_result("Meta não retornou o ID da mídia para envio.") if media_id.blank?

      result.merge(media_id: media_id)
    rescue => e
      error_result(e.message)
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

    def create_template(payload)
      return error_result("Integração não configurada") unless configured? && @integration.waba_id.present?

      url = "#{base}/#{@integration.waba_id}/message_templates"
      response = HTTParty.post(url, headers: auth_headers, body: payload.to_json, timeout: 20)
      parse(response)
    rescue => e
      error_result(e.message)
    end

    def upload_template_media(file_name:, content_type:, byte_size:, io:)
      return error_result("Integração não configurada") unless @integration&.access_token.present?
      return error_result("Upload de mídia para aprovação ainda não está configurado.") if template_upload_app_id.blank?

      session_url = "#{base}/#{template_upload_app_id}/uploads"
      session = parse(HTTParty.post(
        session_url,
        query: {
          access_token: token,
          file_name: file_name,
          file_length: byte_size,
          file_type: content_type
        },
        timeout: 20
      ))
      return session unless session[:ok]

      session_id = session.dig(:data, "id")
      return error_result("Não foi possível iniciar o envio da mídia de exemplo.") if session_id.blank?

      upload_url = "#{base}/#{session_id}"
      io.rewind if io.respond_to?(:rewind)
      upload = parse(HTTParty.post(
        upload_url,
        headers: {
          "Authorization" => "OAuth #{token}",
          "file_offset" => "0",
          "Content-Type" => "application/octet-stream"
        },
        body: io.read,
        timeout: 60
      ))
      return upload unless upload[:ok]

      handle = upload.dig(:data, "h").presence || upload.dig(:data, "handle").presence
      return error_result("Não foi possível concluir o envio da mídia de exemplo.") if handle.blank?

      upload.merge(handle: handle)
    rescue => e
      error_result(e.message)
    end

    def media_url(media_id)
      return error_result("Integração não configurada") unless configured?
      return error_result("Mídia não informada") if media_id.blank?

      response = HTTParty.get("#{base}/#{media_id}", headers: auth_headers, timeout: 15)
      result = parse(response)
      return result unless result[:ok]

      url = result.dig(:data, "url").presence
      return error_result("Meta não retornou a URL da mídia.") if url.blank?

      result.merge(url: url)
    rescue => e
      error_result(e.message)
    end

    def download_media(url)
      return error_result("Integração não configurada") unless configured?
      return error_result("URL da mídia não informada") if url.blank?

      response = HTTParty.get(url, headers: auth_headers.except("Content-Type"), timeout: 30)
      success = response.respond_to?(:success?) ? response.success? : response.code.to_i.between?(200, 299)
      return parse(response) unless success

      {
        ok: true,
        status: response.code,
        data: {},
        body: response.body,
        content_type: response.headers["content-type"].to_s.presence,
        content_length: response.headers["content-length"].to_i,
        disposition: response.headers["content-disposition"].to_s.presence
      }
    rescue => e
      error_result(e.message)
    end

    private

    def post_message(to:, **payload)
      return error_result("Integração não configurada") unless configured?

      url = "#{base}/#{@integration.phone_number_id}/messages"
      body = { messaging_product: "whatsapp", recipient_type: "individual" }.merge(recipient_field(to)).merge(payload)
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

    def template_upload_app_id
      ENV["FACEBOOK_APP_ID"].presence
    end

    def auth_headers
      { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
    end

    # Campo de destinatário da Cloud API:
    # - telefone  -> { to: "<E.164>" }
    # - BSUID     -> { recipient: "<BSUID>" }  (passe `to: { user_id: "<bsuid>" }`)
    # Conforme a doc da Meta: o BSUID vai no campo `recipient` (omitindo `to`).
    # Use o valor inteiro do BSUID (código do país + ponto + alfanumérico).
    def recipient_field(to)
      return { recipient: to[:user_id].to_s } if to.is_a?(Hash) && to[:user_id].present?

      { to: normalize(to) }
    end

    def normalize(phone)
      Phones::Normalizer.call(phone).to_s
    end

    def parse(response)
      data = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        {}
      end
      status_code = response.respond_to?(:code) ? response.code : response.status
      success = response.respond_to?(:success?) ? response.success? : status_code.to_i.between?(200, 299)
      if success
        { ok: true, status: status_code, data: data, message_id: data.dig("messages", 0, "id") }
      else
        meta_error = data["error"].is_a?(Hash) ? data["error"] : {}
        {
          ok: false,
          status: status_code,
          data: data,
          error: meta_error_message(meta_error, status_code),
          meta_error: {
            code: meta_error["code"],
            subcode: meta_error["error_subcode"],
            type: meta_error["type"],
            trace_id: meta_error["fbtrace_id"]
          }.compact
        }
      end
    end

    def error_result(message)
      { ok: false, status: 0, data: {}, error: message }
    end

    def meta_error_message(meta_error, status_code)
      user_message = meta_error["error_user_msg"].presence || meta_error["error_user_title"].presence
      technical_message = meta_error["message"].presence
      [user_message, technical_message].compact_blank.uniq.join(" ")
        .presence || "Erro #{status_code} na comunicação com a Meta."
    end
  end
end
