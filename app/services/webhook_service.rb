class WebhookService
  include HTTParty
  
  TIMEOUT = 5 # segundos

  class << self
    # Envia dados de formulário para o webhook configurado
    # @param origin_form [String] Identificador do formulário (ex: 'contact_form')
    # @param data [Hash] Dados do formulário
    # @param options [Hash] Opções adicionais (ex: :url para override)
    # @return [Boolean] true se ao menos um envio foi disparado
    #
    # O POST roda em background (WebhookDeliveryJob, com retry/backoff no
    # ActiveJob) para não segurar a thread do request/worker. O payload é
    # montado aqui porque options[:request] só existe durante o request.
    def send_form_data(origin_form, data, options = {})
      # If specific URL is provided (e.g. testing), just use that
      if options[:url].present?
        payload = build_payload(origin_form, data, options)
        # O teste do admin precisa do resultado imediato para o feedback na
        # tela; os demais destinos vão para a fila.
        return deliver(options[:url], payload)[:success] if origin_form.to_s == "test_webhook"

        WebhookDeliveryJob.perform_later(options[:url].to_s, payload)
        return true
      end

      active_settings = WebhookSetting.active
      return false if active_settings.empty?

      results = active_settings.map do |setting|
        # Prioritize WhatsApp URL if present (legacy behavior preservation)
        # or maybe we should send to both if both exist?
        # The previous code was: target_url = whatsapp_webhook_url.presence || webhook_url
        # This implies "use WhatsApp URL if set, otherwise standard URL".
        # I will keep this logic for now.
        target_url = setting.whatsapp_webhook_url.presence || setting.webhook_url
        next false if target_url.blank?

        payload = build_payload(origin_form, data, options)
        WebhookDeliveryJob.perform_later(target_url, payload)
        true
      end

      results.any?
    end

    # Entrega única (tentativa individual, sem retry interno — retry/backoff
    # ficam no WebhookDeliveryJob). Nunca levanta exceção.
    # @return [Hash] { success: Boolean, status: Integer|nil, error: String|nil }
    def deliver(url, payload)
      body = payload.to_json
      response = HTTParty.post(
        url,
        body: body,
        headers: {
          'Content-Type' => 'application/json',
          'User-Agent' => 'Salute-Imoveis-Webhook/1.0'
        }.merge(signature_headers(body)),
        timeout: TIMEOUT
      )

      if response.success?
        { success: true, status: response.code, error: nil }
      else
        { success: false, status: response.code, error: "HTTP #{response.code}" }
      end
    rescue StandardError => e
      { success: false, status: nil, error: "#{e.class}: #{e.message}" }
    end

    private
    
    def build_payload(origin_form, data, options = {})
      {
        origin_form: origin_form,
        timestamp: Time.current.iso8601,
        source: source_metadata(options[:request], data),
        data: sanitize_data(data)
      }.compact
    end
    
    def sanitize_data(data)
      # Remove dados sensíveis do Rails
      data.except('authenticity_token', 'commit', 'controller', 'action', 'utf8')
    end

    def source_metadata(request, data)
      metadata = {
        page_url: data["page_url"] || data[:page_url] || data["source_url"] || data[:source_url],
        request_url: request&.original_url,
        referrer_url: data["referrer_url"] || data[:referrer_url] || request&.referer,
        user_agent: request&.user_agent,
        utm: tracking_params(request, data)
      }.compact

      metadata = metadata[:utm].present? ? metadata : metadata.except(:utm)
      metadata.presence
    end

    def tracking_params(request, data)
      params = {}
      request_query = request&.query_parameters || {}
      source_data = data.respond_to?(:to_h) ? data.to_h : {}

      %w[utm_source utm_medium utm_campaign utm_term utm_content gclid fbclid msclkid].each do |key|
        value = source_data[key] || source_data[key.to_sym] || request_query[key] || request_query[key.to_sym]
        params[key] = value if value.present?
      end

      params
    end
    
    def signing_secret
      ENV["WEBHOOK_SIGNING_SECRET"].presence ||
        (Rails.application.credentials.dig(:webhook, :signing_secret) rescue nil)
    end

    # Assinatura HMAC-SHA256 do corpo + timestamp: o receptor confirma que o
    # payload veio de nós e não foi adulterado. Sem segredo configurado, envia
    # sem assinar (compatível com integrações antigas).
    def signature_headers(body)
      secret = signing_secret
      return {} if secret.blank?

      timestamp = Time.current.to_i.to_s
      digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
      {
        "X-Salute-Timestamp" => timestamp,
        "X-Salute-Signature" => "sha256=#{digest}"
      }
    end
  end
end
